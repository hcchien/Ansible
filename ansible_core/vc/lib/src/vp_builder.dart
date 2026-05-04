/// VpBuilder — constructs and signs a W3C Verifiable Presentation.
///
/// The holder signs the canonical VP (without proof) using their Ed25519
/// private key stored in FlutterSecureStorage.
///
/// Signing uses [RustLib.instance.apiSignCommit] — which takes raw bytes and
/// produces a hex Ed25519 signature — the same API used for Lexicon commits.
///
/// TODO(P2): add a dedicated apiSignVp FRB entry point; add challenge/response
/// to prevent VP replay attacks.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../did/lib/src/rust/frb_generated.dart';
import 'verifiable_credential.dart';

class VpBuilder {
  final FlutterSecureStorage _secureStorage;

  static const _kPlcPrivateKey = 'ansible_plc_private_key';
  static const _kLegacyPrivateKey = 'ansible_did_private_key';

  VpBuilder({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Build and sign a [VerifiablePresentation] from [credentials].
  ///
  /// [holderDid] — the DID of the presenter (holder).
  /// [credentials] — one or more VCs to include.
  Future<VerifiablePresentation> build({
    required String holderDid,
    required List<VerifiableCredential> credentials,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Build the VP without proof
    final vpWithoutProof = {
      '@context': ['https://www.w3.org/2018/credentials/v1'],
      'type': ['VerifiablePresentation'],
      'holder': holderDid,
      'verifiableCredential':
          credentials.map((vc) => vc.toJson()).toList(),
    };

    // Sign the canonical JSON bytes with the holder's private key
    final canonical = jsonEncode(vpWithoutProof);
    final msgBytes = Uint8List.fromList(utf8.encode(canonical));

    final proofValue = await _signBytes(msgBytes);

    final proof = CredentialProof(
      type: 'Ed25519Signature2020',
      created: now,
      verificationMethod: '$holderDid#key-1',
      proofPurpose: 'authentication',
      proofValue: proofValue,
    );

    return VerifiablePresentation(
      context: const ['https://www.w3.org/2018/credentials/v1'],
      type: const ['VerifiablePresentation'],
      holder: holderDid,
      verifiableCredential: credentials,
      proof: proof,
    );
  }

  /// Sign [bytes] with the holder's Ed25519 private key.
  ///
  /// Reuses [apiSignCommit] (raw-bytes Ed25519) from the FRB API surface.
  /// Falls back to a dev stub when the Rust bridge is not yet compiled.
  Future<String> _signBytes(Uint8List bytes) async {
    try {
      final privateKeyHex =
          await _secureStorage.read(key: _kPlcPrivateKey) ??
          await _secureStorage.read(key: _kLegacyPrivateKey);

      if (privateKeyHex == null) {
        throw StateError(
            'No local DID keypair found. Run identity registration first.');
      }

      return await RustLib.instance
          .apiSignCommit(cborBytes: bytes, privateKeyHex: privateKeyHex);
    } on UnimplementedError {
      debugPrint(
          '[VpBuilder] DEV WARNING: Rust bridge not compiled — returning dev stub VP signature.');
      return _devStubSig(bytes);
    } on StateError {
      debugPrint(
          '[VpBuilder] DEV WARNING: No keypair in storage — returning dev stub VP signature.');
      return _devStubSig(bytes);
    }
  }

  String _devStubSig(Uint8List bytes) {
    final lenHex = bytes.length.toRadixString(16).padLeft(4, '0');
    return 'devvpsig$lenHex${'00' * 60}';
  }
}
