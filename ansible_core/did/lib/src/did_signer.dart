/// Ed25519 signing for Phase 2 (Daily Operations — lightweight).
///
/// V1.1 Comp B contract: App produces a CRDT Op, then calls [DidSigner.sign]
/// to attach an Ed25519 signature before sending via libp2p Gossipsub.
///
/// The Relay (Comp C) verifies the signature against the cached Verified DID
/// public key in ETS — no ZKP re-run needed.
///
/// Comp A V1.1: delegate to Rust via flutter_rust_bridge.
///   Run flutter_rust_bridge_codegen generate, then uncomment RustLib.instance.* calls.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'rust_api.dart';

/// A detached Ed25519 signature.
class Ed25519Signature {
  /// Raw 64-byte signature, hex-encoded
  final String hex;
  const Ed25519Signature(this.hex);
}

abstract class DidSigner {
  /// Sign [message] bytes using the local DID's Ed25519 private key
  /// (retrieved from Secure Enclave / StrongBox).
  ///
  /// [message] is typically: UTF-8(opId) || payload bytes
  Future<Ed25519Signature> sign(List<int> message);

  /// Verify a signature from a peer DID.
  ///
  /// [publicKeyHex] — hex-encoded Ed25519 public key (32 bytes)
  /// [message]      — original message bytes
  /// [signature]    — [Ed25519Signature] to verify
  static Future<bool> verify({
    required String publicKeyHex,
    required List<int> message,
    required Ed25519Signature signature,
  }) {
    return DidSignerImpl.verify(
      publicKeyHex: publicKeyHex,
      message: message,
      signature: signature,
    );
  }
}

/// Concrete Ed25519 signer backed by the Rust core.
///
/// Private key is loaded from secure storage on each sign call
/// (never held in Dart memory longer than necessary).
class DidSignerImpl implements DidSigner {
  final FlutterSecureStorage _secureStorage;

  DidSignerImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    final privateKeyHex =
        await _secureStorage.read(key: 'ansible_did_private_key');
    if (privateKeyHex == null) {
      throw StateError(
          'No local DID keypair found. Run Identity Anchoring first.');
    }
    final messageHex =
        message.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final sigHex = await RustLib.instance.apiSignMessage(
      privateKeyHex: privateKeyHex,
      messageHex: messageHex,
    );
    return Ed25519Signature(sigHex);
  }

  static Future<bool> verify({
    required String publicKeyHex,
    required List<int> message,
    required Ed25519Signature signature,
  }) async {
    final messageHex =
        message.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return RustLib.instance.apiVerifySignature(
      publicKeyHex: publicKeyHex,
      messageHex: messageHex,
      signatureHex: signature.hex,
    );
  }
}
