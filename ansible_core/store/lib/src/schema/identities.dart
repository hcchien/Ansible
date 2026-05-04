import 'package:drift/drift.dart';

/// Drift table — stores verified DID identities (local + cached peers).
/// Replaces the old `Users` table which held passwordHash.
///
/// V1.1 Comp A: Identity Anchoring cache
class Identities extends Table {
  /// W3C DID, e.g. "did:key:z6Mk..."
  TextColumn get did => text()();

  /// Ed25519 public key, hex-encoded (32 bytes → 64 hex chars)
  TextColumn get publicKey => text()();

  /// Anti-Sybil nullifier: H(passport_secret, domain_salt)
  TextColumn get nullifier => text().unique()();

  /// When the ZKP was accepted by the Relay (Phase 1 completion)
  DateTimeColumn get verifiedAt => dateTime()();

  /// Credential expiry — null = no expiry set
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// true = this device's own identity
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {did};
}
