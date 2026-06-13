import 'package:drift/drift.dart';

/// Local persistence of the self-certifying identity anchor chain (design
/// §"Anchor as a Self-Certifying Object"). The device keeps its own copy of the
/// chain so continuity can be proven without trusting the relay's cache.
///
/// Each row stores both the parsed columns (for querying / ordering) and the
/// full canonical JSON of the anchor (the authoritative, hash-covered form).
@DataClassName('IdentityAnchorRow')
class IdentityAnchors extends Table {
  /// CID of this anchor (`sha256:` of its canonical body) — primary key.
  TextColumn get cid => text()();

  /// DID this anchor belongs to.
  TextColumn get did => text()();

  TextColumn get handle => text()();

  /// Ed25519 identity public key, hex.
  TextColumn get identityKey => text()();

  /// `software` | `hardware`.
  TextColumn get custodyClass => text()();

  /// `initial` | `rotation` | `recovery` | `device_change`.
  TextColumn get reason => text()();

  /// CID of the previous anchor, or null for the genesis anchor.
  TextColumn get prevAnchorCid => text().nullable()();

  /// Monotonic position in the chain (0 = genesis). Used for ordering.
  IntColumn get chainIndex => integer()();

  DateTimeColumn get createdAt => dateTime()();

  /// Full canonical JSON (body + signatures) — the authoritative blob.
  TextColumn get canonicalJson => text()();

  @override
  Set<Column> get primaryKey => {cid};
}
