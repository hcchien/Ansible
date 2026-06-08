/// DID key lifecycle — generate, persist, resolve.
///
/// Key storage backend:
///   iOS  → Secure Enclave (CryptoKit / flutter_secure_storage)
///   Android → StrongBox Keymaster (android_keystore via FFI)
///
/// Comp A V1.1: Rust FFI bridge implemented via flutter_rust_bridge.
///   `frb_generated.dart` is a placeholder stub until you run:
///     ./setup_codegen.sh
///   After codegen the RustLib calls here will use the real native library.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'rust_api.dart';

const _kPrivateKeyStorageKey = 'ansible_did_private_key';
const _kDidStorageKey = 'ansible_did_string';

/// Represents a locally owned DID keypair.
class OwnedDid {
  /// W3C DID string, e.g. "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
  final String did;

  /// Ed25519 public key, hex-encoded (32 bytes)
  final String publicKeyHex;

  const OwnedDid({required this.did, required this.publicKeyHex});
}

abstract class DidManager {
  /// Generate a new Ed25519 keypair and persist the private key in the
  /// platform secure enclave. Returns the resulting [OwnedDid].
  ///
  /// Throws [DidKeygenException] if the enclave is unavailable.
  Future<OwnedDid> generate();

  /// Load the persisted local DID from secure storage.
  /// Returns null if no identity has been anchored yet.
  Future<OwnedDid?> load();

  /// Delete the local DID keypair (e.g. on identity reset).
  Future<void> delete();

  /// Derive the did:key string from a raw Ed25519 public key (32 bytes).
  ///
  /// Encoding: multibase base58btc of (0xed01 || publicKeyBytes)
  /// Spec: https://w3c-ccg.github.io/did-method-key/
  static String encodeDidKey(List<int> publicKeyBytes) {
    return DidManagerImpl.encodeDidKey(publicKeyBytes);
  }
}

/// Concrete implementation that delegates to Rust via flutter_rust_bridge.
///
/// Before this compiles with real FFI calls, run:
///   flutter_rust_bridge_codegen generate
/// from the repo root. Until then, the FFI calls are commented out.
class DidManagerImpl implements DidManager {
  final FlutterSecureStorage _secureStorage;

  DidManagerImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<OwnedDid> generate() async {
    final kp = RustLib.instance.apiGenerateKeypair();
    await _secureStorage.write(
        key: _kPrivateKeyStorageKey, value: kp.privateKeyHex);
    await _secureStorage.write(key: _kDidStorageKey, value: kp.did);
    return OwnedDid(did: kp.did, publicKeyHex: kp.publicKeyHex);
  }

  @override
  Future<OwnedDid?> load() async {
    final did = await _secureStorage.read(key: _kDidStorageKey);
    if (did == null) return null;
    // Re-derive public key from did:key string (no separate storage needed)
    final pubKeyHex = RustLib.instance.apiDecodeDidKey(did: did);
    return OwnedDid(did: did, publicKeyHex: pubKeyHex);
  }

  @override
  Future<void> delete() async {
    await _secureStorage.deleteAll();
  }

  static String encodeDidKey(List<int> publicKeyBytes) {
    final hexStr = publicKeyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return RustLib.instance.apiEncodeDidKey(publicKeyHex: hexStr);
  }
}

class DidKeygenException implements Exception {
  final String message;
  DidKeygenException(this.message);
  @override
  String toString() => 'DidKeygenException: $message';
}
