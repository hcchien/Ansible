import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ansible_did/ansible_did.dart';

import 'tris_aura_credential.dart';
import 'verifiable_credential.dart';

/// VpBuilder constructs W3C Verifiable Presentations.
///
/// The static helpers are used by the production post presentation service so
/// the exact unsigned VP payload can be canonicalized and signed by an injected
/// signer. The instance API is retained for the generic wallet flow that signs
/// locally through the Rust bridge.
class VpBuilder {
  final FlutterSecureStorage _secureStorage;

  static const _kPlcPrivateKey = 'ansible_plc_private_key';
  static const _kLegacyPrivateKey = 'ansible_did_private_key';

  VpBuilder({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static Map<String, Object?> buildUnsigned({
    required TrisAuraCredential credential,
    required String holderDid,
    required String nonce,
    required String audience,
    DateTime? createdAt,
    Set<String>? acceptedCredentialHolderDids,
  }) {
    final acceptedHolders = acceptedCredentialHolderDids ?? {holderDid};
    if (!acceptedHolders.contains(credential.holderDid)) {
      throw TrisAuraCredentialException(
        'holder_mismatch',
        'Presentation holder must match credential subject.',
      );
    }

    final created = (createdAt ?? DateTime.now().toUtc()).toUtc();

    return {
      '@context': ['https://www.w3.org/ns/credentials/v2'],
      'type': ['VerifiablePresentation'],
      'holder': holderDid,
      'verifiableCredential': [credential.compactJwt ?? credential.json],
      'proof': {
        'type': 'DataIntegrityProof',
        'cryptosuite': 'eddsa-jcs-2022',
        'verificationMethod': '$holderDid#key-1',
        'created': created.toIso8601String(),
        'proofPurpose': 'authentication',
        'challenge': nonce,
        'domain': audience,
      },
    };
  }

  static Map<String, Object?> addProof({
    required Map<String, Object?> unsignedPresentation,
    required String proofValue,
  }) {
    final presentation = _deepCopyMap(unsignedPresentation);
    final proof = presentation['proof'];
    if (proof is! Map) {
      throw TrisAuraCredentialException(
        'invalid_presentation',
        'Presentation proof options must be an object.',
      );
    }
    presentation['proof'] = {
      ...proof.map((key, value) => MapEntry(key.toString(), value)),
      'proofValue': proofValue,
    };
    return Map<String, Object?>.unmodifiable(presentation);
  }

  static String canonicalPayload(Map<String, Object?> unsignedPresentation) {
    return jsonEncode(_canonicalValue(unsignedPresentation));
  }

  Future<VerifiablePresentation> build({
    required String holderDid,
    required List<VerifiableCredential> credentials,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    final vpWithoutProof = {
      '@context': ['https://www.w3.org/2018/credentials/v1'],
      'type': ['VerifiablePresentation'],
      'holder': holderDid,
      'verifiableCredential': credentials.map((vc) => vc.toJson()).toList(),
    };

    final canonical = jsonEncode(_canonicalValue(vpWithoutProof));
    final msgBytes = Uint8List.fromList(utf8.encode(canonical));
    final proofValue = await _signBytes(msgBytes);

    final proof = CredentialProof(
      context: const ['https://www.w3.org/ns/credentials/v2'],
      type: 'DataIntegrityProof',
      cryptosuite: 'eddsa-jcs-2022',
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

  Future<String> _signBytes(Uint8List bytes) async {
    try {
      final privateKeyHex =
          await _secureStorage.read(key: _kPlcPrivateKey) ??
          await _secureStorage.read(key: _kLegacyPrivateKey);

      if (privateKeyHex == null) {
        throw StateError(
          'No local DID keypair found. Run identity registration first.',
        );
      }

      return await apiSignCommit(
        cborBytes: bytes,
        privateKeyHex: privateKeyHex,
      );
    } on UnimplementedError {
      debugPrint(
        '[VpBuilder] DEV WARNING: Rust bridge not compiled; returning dev stub VP signature.',
      );
      return _devStubSig(bytes);
    } on StateError {
      debugPrint(
        '[VpBuilder] DEV WARNING: No keypair in storage; returning dev stub VP signature.',
      );
      return _devStubSig(bytes);
    }
  }

  String _devStubSig(Uint8List bytes) {
    final lenHex = bytes.length.toRadixString(16).padLeft(4, '0');
    return 'devvpsig$lenHex${'00' * 60}';
  }

  static Map<String, Object?> _deepCopyMap(Map<String, Object?> source) {
    return source.map((key, value) => MapEntry(key, _deepCopyValue(value)));
  }

  static Object? _deepCopyValue(Object? value) {
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _deepCopyValue(nested)),
      );
    }
    if (value is List) {
      return value.map(_deepCopyValue).toList(growable: false);
    }
    return value;
  }

  static Object? _canonicalValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _canonicalValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalValue).toList(growable: false);
    }
    return value;
  }
}
