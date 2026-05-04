import 'dart:convert';

import 'tris_aura_credential.dart';

class VpBuilder {
  static Map<String, Object?> buildUnsigned({
    required TrisAuraCredential credential,
    required String holderDid,
    required String nonce,
    required String audience,
    DateTime? createdAt,
  }) {
    if (credential.holderDid != holderDid) {
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
      'verifiableCredential': [credential.json],
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

  static Map<String, Object?> build({
    required TrisAuraCredential credential,
    required String holderDid,
    required String nonce,
    required String audience,
    required String proofValue,
    DateTime? createdAt,
  }) {
    return addProof(
      unsignedPresentation: buildUnsigned(
        credential: credential,
        holderDid: holderDid,
        nonce: nonce,
        audience: audience,
        createdAt: createdAt,
      ),
      proofValue: proofValue,
    );
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
