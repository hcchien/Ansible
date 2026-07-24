/// Passkeys-style identity manager for Tris-Aura V2.0.
///
/// On hardware-capable platforms: stores a non-exportable device key and
/// requires local authentication. Windows/Linux may use a separately enabled,
/// explicitly consented reduced-trust software key in OS secure storage.
///
/// "Passkeys" here means: keypair generated and stored in hardware enclave,
/// biometric required to sign, keypair never leaves the device.
///
/// Relay synchronization performs its separate WebAuthn / FIDO2 RP ceremony.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'did_manager.dart';
import 'identity_key.dart';

const _kPasskeysHandleKey = 'ansible_passkeys_handle';
const _kPasskeysDidKey = 'ansible_passkeys_did';
const _kPasskeysPublicKeyKey = 'ansible_passkeys_public_key';
const _kIdentitySigningAlgorithmKey = 'ansible_identity_signing_algorithm';
const _kIdentityCustodyKey = 'ansible_identity_custody';

/// A passkeys-style credential anchored in the device secure enclave.
class PasskeysCredential {
  /// did:key string (did:plc migration in P1 when Rust api_create_did_plc lands)
  final String did;

  /// Ed25519 public key, hex-encoded (32 bytes)
  final String publicKeyHex;

  /// Human-readable handle (username) associated with this credential
  final String handle;
  final IdentityKeyAlgorithm signingAlgorithm;
  final IdentityKeyCustody custody;

  const PasskeysCredential({
    required this.did,
    required this.publicKeyHex,
    required this.handle,
    this.signingAlgorithm = IdentityKeyAlgorithm.ed25519,
    this.custody = IdentityKeyCustody.reducedTrust,
  });
}

abstract class PasskeysManager {
  /// Generate a new keypair with biometric confirmation and store in Secure Enclave.
  /// Returns the resulting [PasskeysCredential].
  Future<PasskeysCredential> register({required String username});

  /// Load existing credential from secure storage.
  /// Returns null if no credential has been registered yet.
  Future<PasskeysCredential?> load();

  /// Check whether biometric / local authentication is available on this device.
  Future<bool> isAvailable();

  /// Delete the stored credential (e.g. on identity reset).
  Future<void> delete();
}

/// Concrete implementation wrapping [DidManagerImpl] with local_auth biometrics.
///
/// Calls [LocalAuthentication.authenticate] before generating/loading keypair.
/// Catches [PlatformException] and proceeds in dev mode if biometrics unavailable.
class PasskeysManagerImpl implements PasskeysManager {
  final DidManagerImpl _didManager;
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;
  final bool _allowInsecureFallback;
  final bool _allowReducedTrustIdentity;
  final HardwareIdentityKey _hardwareKey;

  PasskeysManagerImpl({
    DidManagerImpl? didManager,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuthentication,
    bool allowInsecureFallback = const bool.fromEnvironment(
      'ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK',
      defaultValue: false,
    ),
    bool allowReducedTrustIdentity = false,
    HardwareIdentityKey? hardwareIdentityKey,
  }) : _didManager = didManager ?? DidManagerImpl(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _localAuth = localAuthentication ?? LocalAuthentication(),
       _allowInsecureFallback = allowInsecureFallback,
       _allowReducedTrustIdentity = allowReducedTrustIdentity,
       _hardwareKey = hardwareIdentityKey ?? HardwareIdentityKey();

  Future<bool> _authenticateWithBiometrics({required String reason}) async {
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        if (_allowInsecureFallback || _allowReducedTrustIdentity) {
          debugPrint(
            _allowReducedTrustIdentity
                ? '[PasskeysManager] Device authentication unavailable — explicit reduced-trust identity selected'
                : '[PasskeysManager] Biometrics unavailable — dev fallback enabled',
          );
          return true;
        }
        throw PasskeysAuthException(
          'Biometric or device authentication is not available on this device.',
        );
      }
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false),
      );
    } on PlatformException catch (e) {
      if (_allowInsecureFallback || _allowReducedTrustIdentity) {
        debugPrint(
          '[PasskeysManager] PlatformException from local_auth: $e — ${_allowReducedTrustIdentity ? 'explicit reduced-trust mode' : 'dev fallback enabled'}',
        );
        return true;
      }
      throw PasskeysAuthException(
        'Device authentication failed: ${e.message ?? e.code}',
      );
    } catch (e) {
      if (_allowInsecureFallback || _allowReducedTrustIdentity) {
        debugPrint(
          '[PasskeysManager] local_auth threw $e — ${_allowReducedTrustIdentity ? 'explicit reduced-trust mode' : 'dev fallback enabled'}',
        );
        return true;
      }
      rethrow;
    }
  }

  @override
  Future<PasskeysCredential> register({required String username}) async {
    final authed = await _authenticateWithBiometrics(
      reason: 'Confirm your identity to create a Tris-Aura account',
    );
    if (!authed) {
      throw PasskeysAuthException('Biometric authentication was not confirmed');
    }

    IdentityPublicKey identityKey;
    String did;
    try {
      identityKey = await _hardwareKey.generate();
      did = 'did:key:p256:${identityKey.publicKeyHex.substring(0, 24)}';
    } catch (error) {
      if (!(_allowInsecureFallback || _allowReducedTrustIdentity) ||
          (error is! PlatformException && error is! MissingPluginException)) {
        rethrow;
      }
      final ownedDid = await _didManager.generate();
      identityKey = IdentityPublicKey(
        algorithm: IdentityKeyAlgorithm.ed25519,
        publicKeyHex: ownedDid.publicKeyHex,
        custody: IdentityKeyCustody.reducedTrust,
        hardwareSecurityLevel: _allowReducedTrustIdentity
            ? 'software_os_secure_storage'
            : 'software_dev_fallback',
      );
      did = ownedDid.did;
    }

    await _secureStorage.write(key: _kPasskeysHandleKey, value: username);
    await _secureStorage.write(key: _kPasskeysDidKey, value: did);
    await _secureStorage.write(
      key: _kPasskeysPublicKeyKey,
      value: identityKey.publicKeyHex,
    );
    await _secureStorage.write(
      key: _kIdentitySigningAlgorithmKey,
      value: identityKey.algorithm.wireName,
    );
    await _secureStorage.write(
      key: _kIdentityCustodyKey,
      value: identityKey.custody.wireName,
    );

    return PasskeysCredential(
      did: did,
      publicKeyHex: identityKey.publicKeyHex,
      handle: username,
      signingAlgorithm: identityKey.algorithm,
      custody: identityKey.custody,
    );
  }

  @override
  Future<PasskeysCredential?> load() async {
    final did = await _secureStorage.read(key: _kPasskeysDidKey);
    if (did == null) return null;

    final authed = await _authenticateWithBiometrics(
      reason: 'Confirm your identity to sign in to Tris-Aura',
    );
    if (!authed) {
      throw PasskeysAuthException('Biometric authentication was not confirmed');
    }

    final publicKeyHex = await _secureStorage.read(key: _kPasskeysPublicKeyKey);
    final handle = await _secureStorage.read(key: _kPasskeysHandleKey);
    final algorithm = await _secureStorage.read(
      key: _kIdentitySigningAlgorithmKey,
    );
    final custody = await _secureStorage.read(key: _kIdentityCustodyKey);

    if (publicKeyHex == null || handle == null) return null;

    return PasskeysCredential(
      did: did,
      publicKeyHex: publicKeyHex,
      handle: handle,
      signingAlgorithm: algorithm == null
          ? IdentityKeyAlgorithm.ed25519
          : IdentityKeyAlgorithm.parse(algorithm),
      custody: custody == IdentityKeyCustody.hardware.wireName
          ? IdentityKeyCustody.hardware
          : IdentityKeyCustody.reducedTrust,
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException catch (e) {
      debugPrint('[PasskeysManager] isAvailable PlatformException: $e');
      return false;
    }
  }

  @override
  Future<void> delete() async {
    await _secureStorage.delete(key: _kPasskeysHandleKey);
    await _secureStorage.delete(key: _kPasskeysDidKey);
    await _secureStorage.delete(key: _kPasskeysPublicKeyKey);
    await _secureStorage.delete(key: _kIdentitySigningAlgorithmKey);
    await _secureStorage.delete(key: _kIdentityCustodyKey);
    await _hardwareKey.delete();
    await _didManager.delete();
  }
}

/// Stub implementation for CI / widget tests.
///
/// Returns a deterministic dev credential without touching biometrics or storage.
class PasskeysManagerStub implements PasskeysManager {
  static const _stubDid = 'did:key:stub-dev-credential';
  static const _stubPublicKeyHex =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

  @override
  Future<PasskeysCredential> register({required String username}) async {
    debugPrint('[PasskeysManagerStub] register called — returning dev stub');
    return PasskeysCredential(
      did: _stubDid,
      publicKeyHex: _stubPublicKeyHex,
      handle: username,
    );
  }

  @override
  Future<PasskeysCredential?> load() async {
    debugPrint('[PasskeysManagerStub] load called — returning dev stub');
    return const PasskeysCredential(
      did: _stubDid,
      publicKeyHex: _stubPublicKeyHex,
      handle: 'stub-user',
    );
  }

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> delete() async {
    debugPrint('[PasskeysManagerStub] delete called — no-op in stub');
  }
}

/// Thrown when biometric authentication is required but not confirmed.
class PasskeysAuthException implements Exception {
  final String message;
  PasskeysAuthException(this.message);
  @override
  String toString() => 'PasskeysAuthException: $message';
}
