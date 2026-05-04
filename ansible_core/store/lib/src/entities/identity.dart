/// Represents a verified DID identity anchored via Phase 1 (NFC passport + ZKP).
///
/// V1.1 Comp A: Identity Anchoring
/// - [did]        — W3C DID string, e.g. "did:key:z6Mk..."
/// - [publicKey]  — Ed25519 public key bytes (32 bytes, hex-encoded)
/// - [nullifier]  — Sybil-resistance hash: one passport → one nullifier
/// - [verifiedAt] — Timestamp when the ZKP was accepted by the Relay
/// - [expiresAt]  — Credential expiry; after this, Phase 1 must be re-run
/// - [isLocal]    — true = this device's own identity; false = peer (from relay)
class Identity {
  final String did;
  final String publicKey; // Ed25519 public key, hex-encoded
  final String nullifier; // H(passport_secret, domain_salt) — anti-Sybil
  final DateTime verifiedAt;
  final DateTime? expiresAt;
  final bool isLocal;

  const Identity({
    required this.did,
    required this.publicKey,
    required this.nullifier,
    required this.verifiedAt,
    this.expiresAt,
    this.isLocal = false,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'did': did,
        'publicKey': publicKey,
        'nullifier': nullifier,
        'verifiedAt': verifiedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'isLocal': isLocal,
      };

  factory Identity.fromJson(Map<String, dynamic> json) => Identity(
        did: json['did'] as String,
        publicKey: json['publicKey'] as String,
        nullifier: json['nullifier'] as String,
        verifiedAt: DateTime.parse(json['verifiedAt'] as String),
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        isLocal: json['isLocal'] as bool? ?? false,
      );
}
