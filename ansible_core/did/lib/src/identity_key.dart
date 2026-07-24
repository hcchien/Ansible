import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Algorithms accepted by the Elix identity protocol.
enum IdentityKeyAlgorithm {
  ed25519('ed25519'),
  p256Sha256('p256-sha256');

  const IdentityKeyAlgorithm(this.wireName);
  final String wireName;

  static IdentityKeyAlgorithm parse(String value) => values.firstWhere(
    (algorithm) => algorithm.wireName == value,
    orElse: () => throw ArgumentError.value(value, 'value'),
  );
}

enum IdentityKeyCustody {
  software('software'),
  hardware('hardware'),
  reducedTrust('reduced_trust');

  const IdentityKeyCustody(this.wireName);
  final String wireName;
}

class IdentityPublicKey {
  const IdentityPublicKey({
    required this.algorithm,
    required this.publicKeyHex,
    required this.custody,
    this.hardwareSecurityLevel,
  });

  final IdentityKeyAlgorithm algorithm;
  final String publicKeyHex;
  final IdentityKeyCustody custody;
  final String? hardwareSecurityLevel;
}

class IdentitySignature {
  const IdentitySignature({required this.algorithm, required this.hex});
  final IdentityKeyAlgorithm algorithm;
  final String hex;
}

class HardwareAgreementPublicKey {
  const HardwareAgreementPublicKey({
    required this.publicKeyHex,
    required this.custody,
    this.hardwareSecurityLevel,
  });

  final String publicKeyHex;
  final IdentityKeyCustody custody;
  final String? hardwareSecurityLevel;
}

/// Non-exportable P-256 identity key held by Secure Enclave or Android
/// Keystore. Only public material and signatures cross the platform channel.
class HardwareIdentityKey {
  HardwareIdentityKey({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('elix/hardware_identity_key');

  final MethodChannel _channel;

  Future<IdentityPublicKey> generate({
    String alias = 'elix.identity.v1',
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('generate', {
      'alias': alias,
    });
    return _decode(result);
  }

  Future<IdentityPublicKey?> load({String alias = 'elix.identity.v1'}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('load', {
      'alias': alias,
    });
    return result == null ? null : _decode(result);
  }

  Future<IdentitySignature> sign(
    List<int> message, {
    String alias = 'elix.identity.v1',
    bool reuseAuthenticationContext = false,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('sign', {
      'alias': alias,
      'message': Uint8List.fromList(message),
      'reuse_authentication_context': reuseAuthenticationContext,
    });
    final signatureHex = result?['signature_hex'] as String?;
    if (signatureHex == null || signatureHex.isEmpty) {
      throw StateError('Hardware identity key did not return a signature.');
    }
    return IdentitySignature(
      algorithm: IdentityKeyAlgorithm.p256Sha256,
      hex: signatureHex,
    );
  }

  Future<void> delete({String alias = 'elix.identity.v1'}) async {
    await _channel.invokeMethod<void>('delete', {'alias': alias});
  }

  Future<bool> verify({
    required String publicKeyHex,
    required List<int> message,
    required String signatureHex,
  }) async {
    return await _channel.invokeMethod<bool>('verify', {
          'public_key_hex': publicKeyHex,
          'message': Uint8List.fromList(message),
          'signature_hex': signatureHex,
        }) ??
        false;
  }

  Future<HardwareAgreementPublicKey> generateAgreement({
    required String alias,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'generateAgreement',
      {'alias': alias},
    );
    return _decodeAgreement(result);
  }

  Future<HardwareAgreementPublicKey?> loadAgreement({
    required String alias,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'loadAgreement',
      {'alias': alias},
    );
    return result == null ? null : _decodeAgreement(result);
  }

  /// Performs P-256 ECDH inside the hardware keystore. Only the derived
  /// 32-byte secret leaves the platform boundary; private key bytes never do.
  Future<Uint8List> deriveAgreement({
    required String alias,
    required String peerPublicKeyHex,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>('deriveAgreement', {
      'alias': alias,
      'peer_public_key_hex': peerPublicKeyHex,
    });
    if (result == null || result.length != 32) {
      throw StateError('Hardware key agreement did not return 32 bytes.');
    }
    return result;
  }

  Future<void> deleteAgreement({required String alias}) async {
    await _channel.invokeMethod<void>('deleteAgreement', {'alias': alias});
  }

  IdentityPublicKey _decode(Map<String, dynamic>? result) {
    if (result == null) throw StateError('Hardware key operation failed.');
    final publicKeyHex = result['public_key_hex'] as String?;
    if (publicKeyHex == null || publicKeyHex.length != 130) {
      throw const FormatException('Expected an uncompressed P-256 public key.');
    }
    final custodyName = result['custody'] as String?;
    final custody = IdentityKeyCustody.values.firstWhere(
      (value) => value.wireName == custodyName,
      orElse: () => throw const FormatException(
        'Platform did not report a recognized key custody level.',
      ),
    );
    return IdentityPublicKey(
      algorithm: IdentityKeyAlgorithm.p256Sha256,
      publicKeyHex: publicKeyHex,
      custody: custody,
      hardwareSecurityLevel: result['hardware_security_level'] as String?,
    );
  }

  HardwareAgreementPublicKey _decodeAgreement(Map<String, dynamic>? result) {
    if (result == null) throw StateError('Hardware key operation failed.');
    final publicKeyHex = result['public_key_hex'] as String?;
    if (publicKeyHex == null || publicKeyHex.length != 130) {
      throw const FormatException('Expected an uncompressed P-256 public key.');
    }
    final custodyName = result['custody'] as String?;
    final custody = IdentityKeyCustody.values.firstWhere(
      (value) => value.wireName == custodyName,
      orElse: () => throw const FormatException(
        'Platform did not report a recognized key custody level.',
      ),
    );
    return HardwareAgreementPublicKey(
      publicKeyHex: publicKeyHex,
      custody: custody,
      hardwareSecurityLevel: result['hardware_security_level'] as String?,
    );
  }
}

/// A short-lived, user-approved hardware signing window for one explicit user
/// operation (currently sync). It never weakens the per-request signature:
/// callers still create a distinct nonce-bound proof for every operation.
///
/// iOS retains the authorized `LAContext` only until [close]. Platforms that
/// do not implement the channel return `null`, so callers retain their normal
/// per-operation hardware authorization behavior.
class HardwareAuthenticationSession {
  HardwareAuthenticationSession._(this._channel);

  final MethodChannel _channel;

  static Future<HardwareAuthenticationSession?> begin({
    required String localizedReason,
    MethodChannel? channel,
  }) async {
    final methodChannel =
        channel ?? const MethodChannel('elix/hardware_identity_key');

    try {
      final started = await methodChannel.invokeMethod<bool>(
        'beginAuthenticationSession',
        {'localized_reason': localizedReason},
      );
      return started == true
          ? HardwareAuthenticationSession._(methodChannel)
          : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('endAuthenticationSession');
    } on MissingPluginException {
      // The platform has no reusable authentication context.
    } on PlatformException {
      // The session is best-effort cleanup; expired contexts are fail-closed.
    }
  }
}

/// Purpose-separated non-exportable signing keys. Aliases are protocol
/// constants so identity, Wallet holder binding, Issuer administration, and
/// board-device authorization can never accidentally share private material.
enum HardwareKeyPurpose {
  identity('elix.identity.v1'),
  walletHolderBinding('elix.wallet.holder-binding.v1'),
  boardHolderBinding('elix.wallet.board-holder-binding.v1'),
  issuerRootAdministration('elix.issuer.root-admin.v1'),
  boardDeviceAuthorization('elix.board.device-auth.v1'),
  boardContentKeyAgreement('elix.board.content-ecdh.v1');

  const HardwareKeyPurpose(this.alias);
  final String alias;
}

/// A context-scoped signing key whose private material remains non-exportable.
///
/// The context is hashed before it reaches the platform keystore so board IDs
/// are not exposed through key aliases. A different board therefore gets a
/// cryptographically unrelated holder key and cannot be correlated from its
/// public key or did:jwk identifier.
class HardwareScopedPurposeKey {
  HardwareScopedPurposeKey(
    this.purpose, {
    required String context,
    HardwareIdentityKey? platformKey,
  }) : _alias =
           '${purpose.alias}.${sha256.convert(utf8.encode(context.trim()))}',
       _platformKey = platformKey ?? HardwareIdentityKey() {
    if (context.trim().isEmpty) {
      throw ArgumentError.value(context, 'context');
    }
  }

  final HardwareKeyPurpose purpose;
  final String _alias;
  final HardwareIdentityKey _platformKey;

  Future<IdentityPublicKey> generate() =>
      _requireHardware(_platformKey.generate(alias: _alias));

  Future<IdentityPublicKey?> load() async {
    final key = await _platformKey.load(alias: _alias);
    return key == null ? null : _requireHardware(Future.value(key));
  }

  Future<IdentitySignature> sign(
    List<int> message, {
    bool reuseAuthenticationContext = false,
  }) => _platformKey.sign(
    message,
    alias: _alias,
    reuseAuthenticationContext: reuseAuthenticationContext,
  );

  Future<void> delete() => _platformKey.delete(alias: _alias);

  Future<IdentityPublicKey> _requireHardware(
    Future<IdentityPublicKey> pending,
  ) async {
    final key = await pending;
    if (key.custody != IdentityKeyCustody.hardware) {
      throw StateError('Scoped holder keys require hardware custody.');
    }
    return key;
  }
}

class HardwarePurposeAgreementKey {
  HardwarePurposeAgreementKey({
    required String boardId,
    HardwareIdentityKey? platformKey,
  }) : _alias =
           '${HardwareKeyPurpose.boardContentKeyAgreement.alias}.${sha256.convert(utf8.encode(boardId))}',
       _platformKey = platformKey ?? HardwareIdentityKey() {
    if (boardId.trim().isEmpty) {
      throw ArgumentError.value(boardId, 'boardId');
    }
  }

  static const purpose = HardwareKeyPurpose.boardContentKeyAgreement;
  final String _alias;
  final HardwareIdentityKey _platformKey;

  Future<HardwareAgreementPublicKey> generate() async {
    return _requireHardware(
      await _platformKey.generateAgreement(alias: _alias),
    );
  }

  Future<HardwareAgreementPublicKey?> load() async {
    final key = await _platformKey.loadAgreement(alias: _alias);
    return key == null ? null : _requireHardware(key);
  }

  Future<Uint8List> derive(String peerPublicKeyHex) => _platformKey
      .deriveAgreement(alias: _alias, peerPublicKeyHex: peerPublicKeyHex);

  Future<void> delete() => _platformKey.deleteAgreement(alias: _alias);

  HardwareAgreementPublicKey _requireHardware(HardwareAgreementPublicKey key) {
    if (key.custody != IdentityKeyCustody.hardware) {
      throw StateError('Private boards require hardware-backed key agreement.');
    }
    return key;
  }
}

class HardwarePurposeKey {
  HardwarePurposeKey(this.purpose, {HardwareIdentityKey? platformKey})
    : _platformKey = platformKey ?? HardwareIdentityKey();

  final HardwareKeyPurpose purpose;
  final HardwareIdentityKey _platformKey;

  Future<IdentityPublicKey> generate() =>
      _platformKey.generate(alias: purpose.alias);

  Future<IdentityPublicKey?> load() => _platformKey.load(alias: purpose.alias);

  Future<IdentitySignature> sign(
    List<int> message, {
    bool reuseAuthenticationContext = false,
  }) => _platformKey.sign(
    message,
    alias: purpose.alias,
    reuseAuthenticationContext: reuseAuthenticationContext,
  );

  Future<void> delete() => _platformKey.delete(alias: purpose.alias);
}
