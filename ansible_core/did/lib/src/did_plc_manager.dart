/// did:plc identity manager — wraps Rust api_create_did_plc FFI.
///
/// In P1 Alpha the PLC directory registration is a POST to the relay
/// (/api/v2/identity/register). The Relay proxies to plc.directory in
/// production; in dev it stores locally.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'rust/frb_generated.dart';

const _kPlcDidKey = 'ansible_plc_did';
const _kPlcGenesisKey = 'ansible_plc_genesis_json';
const _kPlcPublicKeyKey = 'ansible_plc_public_key';
const _kPlcPrivateKeyKey = 'ansible_plc_private_key';

/// Result of creating or loading a did:plc identity.
class DidPlcResult {
  /// The did:plc string, e.g. "did:plc:abcdef1234567890"
  final String did;

  /// JSON-encoded genesis operation for PLC directory submission
  final String genesisJson;

  /// Ed25519 public key, hex-encoded (32 bytes)
  final String publicKeyHex;

  const DidPlcResult({
    required this.did,
    required this.genesisJson,
    required this.publicKeyHex,
  });
}

abstract class DidPlcManager {
  /// Create a new did:plc by generating a keypair and submitting the genesis op.
  ///
  /// [handle] — the AT Protocol handle (e.g. "alice.elix.cool")
  /// [pdsEndpoint] — the PDS service endpoint to embed in the genesis op
  /// [signingKeyHex] — optional existing Ed25519 public key to use as the
  /// PLC signing key. When omitted, a fresh keypair is generated.
  Future<DidPlcResult> createDid({
    required String handle,
    String pdsEndpoint = 'https://elix.cool',
    String? signingKeyHex,
  });

  /// Load an existing did:plc from secure storage.
  /// Returns null if no did:plc has been created yet.
  Future<DidPlcResult?> loadDid();

  /// Delete the stored did:plc keypair and metadata.
  Future<void> deleteDid();
}

/// Concrete implementation that delegates to Rust via flutter_rust_bridge.
///
/// Key generation flow:
///   1. [RustLib.instance.apiGenerateKeypair] → fresh Ed25519 keypair
///   2. [RustLib.instance.apiCreateDidPlc]    → genesis op JSON + did:plc string
///   3. Store private key, did, genesisJson in FlutterSecureStorage
class DidPlcManagerImpl implements DidPlcManager {
  final FlutterSecureStorage _secureStorage;
  final bool _allowInsecureFallback;

  DidPlcManagerImpl({
    FlutterSecureStorage? secureStorage,
    bool allowInsecureFallback = const bool.fromEnvironment(
      'ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK',
      defaultValue: false,
    ),
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _allowInsecureFallback = allowInsecureFallback;

  @override
  Future<DidPlcResult> createDid({
    required String handle,
    String pdsEndpoint = 'https://elix.cool',
    String? signingKeyHex,
  }) async {
    try {
      if (signingKeyHex != null && !_isEd25519PublicKeyHex(signingKeyHex)) {
        throw DidPlcException(
          'Invalid Ed25519 public key for did:plc creation.',
        );
      }

      // Reuse the passkeys public key when provided so did:plc and the
      // registration signature refer to the same device-held credential.
      final kp = signingKeyHex == null
          ? RustLib.instance.apiGenerateKeypair()
          : null;
      final publicKeyHex = signingKeyHex ?? kp!.publicKeyHex;

      // Build genesis op via Rust; returns did:plc string + genesis JSON
      final plcResult = await RustLib.instance.apiCreateDidPlc(
        signingKeyHex: publicKeyHex,
        handle: handle,
        pdsEndpoint: pdsEndpoint,
      );

      _validateProductionPlcResult(plcResult);

      // Persist to secure storage
      if (kp != null) {
        await _secureStorage.write(
          key: _kPlcPrivateKeyKey,
          value: kp.privateKeyHex,
        );
      }
      await _secureStorage.write(key: _kPlcDidKey, value: plcResult.did);
      await _secureStorage.write(
        key: _kPlcGenesisKey,
        value: plcResult.genesisJson,
      );
      await _secureStorage.write(key: _kPlcPublicKeyKey, value: publicKeyHex);

      return DidPlcResult(
        did: plcResult.did,
        genesisJson: plcResult.genesisJson,
        publicKeyHex: publicKeyHex,
      );
    } on UnimplementedError catch (e) {
      if (!_allowInsecureFallback) {
        throw DidPlcException(
          'Native did:plc generation is not available. Run code generation and bundle the Rust library before registration.',
        );
      }
      debugPrint(
        '[DidPlcManager] DEV WARNING: apiCreateDidPlc not implemented in Rust stub — '
        'returning dev did:plc. Error: $e',
      );
      const stubDid = 'did:plc:dev-stub-placeholder';
      const stubGenesis = '{"type":"plc_genesis","stub":true}';
      const stubPubKey =
          '0000000000000000000000000000000000000000000000000000000000000000';
      await _secureStorage.write(key: _kPlcDidKey, value: stubDid);
      await _secureStorage.write(key: _kPlcGenesisKey, value: stubGenesis);
      await _secureStorage.write(key: _kPlcPublicKeyKey, value: stubPubKey);
      return const DidPlcResult(
        did: stubDid,
        genesisJson: stubGenesis,
        publicKeyHex: stubPubKey,
      );
    }
  }

  @override
  Future<DidPlcResult?> loadDid() async {
    final did = await _secureStorage.read(key: _kPlcDidKey);
    if (did == null) return null;

    final genesisJson = await _secureStorage.read(key: _kPlcGenesisKey);
    final publicKeyHex = await _secureStorage.read(key: _kPlcPublicKeyKey);

    if (genesisJson == null || publicKeyHex == null) return null;

    return DidPlcResult(
      did: did,
      genesisJson: genesisJson,
      publicKeyHex: publicKeyHex,
    );
  }

  @override
  Future<void> deleteDid() async {
    await _secureStorage.delete(key: _kPlcDidKey);
    await _secureStorage.delete(key: _kPlcGenesisKey);
    await _secureStorage.delete(key: _kPlcPublicKeyKey);
    await _secureStorage.delete(key: _kPlcPrivateKeyKey);
  }

  void _validateProductionPlcResult(DidPlcBytes result) {
    if (_allowInsecureFallback) return;

    final validDid = RegExp(r'^did:plc:[a-z2-7]{10,}$').hasMatch(result.did);
    final looksLikeStub =
        result.did.contains('dev-') ||
        result.genesisJson.contains('"stub":true');
    final hasSignedGenesisOp = _hasSignedGenesisOp(result.genesisJson);

    if (!validDid || looksLikeStub || !hasSignedGenesisOp) {
      throw DidPlcException(
        'Native did:plc generation returned an invalid or development placeholder. '
        'Ensure the Rust library is built and run setup_codegen.sh before registration.',
      );
    }
  }

  /// Validate the structure of a genesis op JSON returned by the Rust FFI.
  ///
  /// P1 (current): Rust produces a JSON-serialised genesis op with
  ///   "type": "plc_genesis" and no "sig" field.  The DID suffix is derived
  ///   from SHA-256 of this JSON (not DAG-CBOR), so these DIDs are local-only
  ///   and NOT compatible with the live plc.directory.
  ///
  /// TODO(P2): when did_plc.rs switches to DAG-CBOR hashing and includes a
  ///   signed genesis op, update this check to:
  ///     decoded['type'] == 'plc_operation'   (real AT-Proto PLC type)
  ///     decoded['sig'] is String             (Ed25519 signature present)
  bool _hasSignedGenesisOp(String genesisJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(genesisJson);
    } catch (_) {
      return false;
    }

    if (decoded is! Map<String, dynamic>) return false;

    // P1: accept "plc_genesis" (Rust did_plc.rs output, unsigned, JSON-hashed)
    // P2: change to 'plc_operation' once Rust emits a signed CBOR-hashed op.
    return decoded['type'] == 'plc_genesis' &&
        decoded['prev'] == null &&
        decoded['signingKey'] is String &&
        decoded['rotationKeys'] is List &&
        decoded['services'] is Map;
  }

  bool _isEd25519PublicKeyHex(String value) {
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
  }
}

class DidPlcException implements Exception {
  final String message;
  const DidPlcException(this.message);

  @override
  String toString() => 'DidPlcException: $message';
}
