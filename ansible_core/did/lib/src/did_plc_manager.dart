/// did:plc identity manager — LEGACY read path only.
///
/// The canonical identity is now `did:elix` (derived from the identity key +
/// handle). `did:plc` *creation* has been retired: a real did:plc is only ever
/// minted by the future opt-in Bluesky bridge (Phase D), which will write its
/// own DAG-CBOR genesis. This manager survives solely to LOAD a pre-did:elix
/// account's stored did:plc as a boot-time fallback (see `main.dart`).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kPlcDidKey = 'ansible_plc_did';
const _kPlcGenesisKey = 'ansible_plc_genesis_json';
const _kPlcPublicKeyKey = 'ansible_plc_public_key';
const _kPlcPrivateKeyKey = 'ansible_plc_private_key';

/// Result of loading a stored did:plc identity.
class DidPlcResult {
  /// The did:plc string, e.g. "did:plc:abcdef1234567890"
  final String did;

  /// JSON-encoded genesis operation kept from creation.
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
  /// Load an existing did:plc from secure storage.
  /// Returns null if no did:plc has been stored (i.e. a did:elix-native account).
  Future<DidPlcResult?> loadDid();

  /// Delete the stored did:plc keypair and metadata.
  Future<void> deleteDid();
}

/// Concrete implementation backed by `flutter_secure_storage`.
class DidPlcManagerImpl implements DidPlcManager {
  final FlutterSecureStorage _secureStorage;

  DidPlcManagerImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

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
}
