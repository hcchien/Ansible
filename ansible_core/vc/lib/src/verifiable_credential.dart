/// W3C Verifiable Credential and Verifiable Presentation models.
/// https://www.w3.org/TR/vc-data-model/
///
/// Proof encoding:
///   DataIntegrityProof / eddsa-jcs-2022 with multibase base58-btc proofValue.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─── Proof ───────────────────────────────────────────────────────────────────

class CredentialProof {
  final List<String>? context;
  final String type;
  final String? cryptosuite;
  final String created;
  final String verificationMethod;
  final String proofPurpose;
  final String proofValue;

  /// Challenge nonce — required for VP authentication proofs (prevents replay).
  final String? challenge;

  const CredentialProof({
    this.context,
    required this.type,
    this.cryptosuite,
    required this.created,
    required this.verificationMethod,
    required this.proofPurpose,
    required this.proofValue,
    this.challenge,
  });

  factory CredentialProof.fromJson(Map<String, dynamic> json) =>
      CredentialProof(
        context: _optionalContext(json['@context']),
        type: json['type'] as String,
        cryptosuite: json['cryptosuite'] as String?,
        created: json['created'] as String,
        verificationMethod: json['verificationMethod'] as String,
        proofPurpose: json['proofPurpose'] as String,
        proofValue: json['proofValue'] as String,
        challenge: json['challenge'] as String?,
      );

  Map<String, dynamic> toJson() => {
    if (context != null) '@context': context,
    'type': type,
    if (cryptosuite != null) 'cryptosuite': cryptosuite,
    'created': created,
    'verificationMethod': verificationMethod,
    'proofPurpose': proofPurpose,
    'proofValue': proofValue,
    if (challenge != null) 'challenge': challenge,
  };

  static List<String>? _optionalContext(Object? value) {
    if (value == null) return null;
    if (value is String) return [value];
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    throw const FormatException(
      'Credential proof @context must be a string list.',
    );
  }
}

// ─── VerifiableCredential ────────────────────────────────────────────────────

class VerifiableCredential {
  final List<String> context;
  final String id;
  final List<String> type;
  final String issuer;
  final String issuanceDate;
  final String? expirationDate;
  final Map<String, dynamic> credentialSubject;
  final CredentialProof proof;

  const VerifiableCredential({
    required this.context,
    required this.id,
    required this.type,
    required this.issuer,
    required this.issuanceDate,
    this.expirationDate,
    required this.credentialSubject,
    required this.proof,
  });

  factory VerifiableCredential.fromJson(Map<String, dynamic> json) =>
      VerifiableCredential(
        context: (json['@context'] as List).cast<String>(),
        id: json['id'] as String,
        type: (json['type'] as List).cast<String>(),
        issuer: json['issuer'] as String,
        issuanceDate: json['issuanceDate'] as String,
        expirationDate: json['expirationDate'] as String?,
        credentialSubject: json['credentialSubject'] as Map<String, dynamic>,
        proof: CredentialProof.fromJson(json['proof'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
    '@context': context,
    'id': id,
    'type': type,
    'issuer': issuer,
    'issuanceDate': issuanceDate,
    if (expirationDate != null) 'expirationDate': expirationDate,
    'credentialSubject': credentialSubject,
    'proof': proof.toJson(),
  };

  /// True if the VC has passed its expirationDate.
  bool get isExpired {
    if (expirationDate == null) return false;
    final expiry = DateTime.tryParse(expirationDate!);
    return expiry != null && DateTime.now().isAfter(expiry);
  }

  /// The DID of the credential subject (holder).
  String? get holderDid => credentialSubject['id'] as String?;

  /// True if this is an EmailCredential issued by a Tris-Aura issuer.
  bool get isEmailCredential => type.contains('EmailCredential');
}

// ─── VerifiablePresentation ──────────────────────────────────────────────────

class VerifiablePresentation {
  final List<String> context;
  final List<String> type;
  final String holder;
  final List<VerifiableCredential> verifiableCredential;
  final CredentialProof proof;

  const VerifiablePresentation({
    required this.context,
    required this.type,
    required this.holder,
    required this.verifiableCredential,
    required this.proof,
  });

  Map<String, dynamic> toJson() => {
    '@context': context,
    'type': type,
    'holder': holder,
    'verifiableCredential': verifiableCredential
        .map((vc) => vc.toJson())
        .toList(),
    'proof': proof.toJson(),
  };

  /// Serialise the VP *without* the proof field (canonical form for signing /
  /// verification).
  Map<String, dynamic> toJsonWithoutProof() => {
    '@context': context,
    'type': type,
    'holder': holder,
    'verifiableCredential': verifiableCredential
        .map((vc) => vc.toJson())
        .toList(),
  };
}

// ─── CredentialWallet ────────────────────────────────────────────────────────

/// Thin wrapper around [FlutterSecureStorage] for persisting received VCs.
///
/// Each credential is stored as JSON under the key
/// `ansible_vc_<sanitised_credential_id>`.
class CredentialWallet {
  static const _kPrefix = 'ansible_vc_';
  static const _kIndexKey = 'ansible_vc_index';

  final FlutterSecureStorage _storage;

  const CredentialWallet({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Store a [VerifiableCredential]. Overwrites any existing entry with the
  /// same id.
  Future<void> store(VerifiableCredential vc) async {
    final key = _storageKey(vc.id);
    await _storage.write(key: key, value: jsonEncode(vc.toJson()));

    // Update index
    final existing = await _readIndex();
    if (!existing.contains(vc.id)) {
      existing.add(vc.id);
      await _storage.write(key: _kIndexKey, value: jsonEncode(existing));
    }
  }

  /// Load all stored [VerifiableCredential]s.
  Future<List<VerifiableCredential>> loadAll() async {
    final ids = await _readIndex();
    final results = <VerifiableCredential>[];
    for (final id in ids) {
      final raw = await _storage.read(key: _storageKey(id));
      if (raw != null) {
        try {
          results.add(
            VerifiableCredential.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            ),
          );
        } catch (_) {
          // Skip malformed entries
        }
      }
    }
    return results;
  }

  /// Delete a credential by its id.
  Future<void> delete(String vcId) async {
    await _storage.delete(key: _storageKey(vcId));
    final index = await _readIndex()
      ..remove(vcId);
    await _storage.write(key: _kIndexKey, value: jsonEncode(index));
  }

  Future<List<String>> _readIndex() async {
    final raw = await _storage.read(key: _kIndexKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  String _storageKey(String vcId) {
    // Sanitise the VC id (a URL) into a safe storage key.
    final safe = vcId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '$_kPrefix$safe';
  }
}
