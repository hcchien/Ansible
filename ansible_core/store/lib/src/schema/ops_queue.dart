import 'package:drift/drift.dart';

/// Drift table — local CRDT Op queue (Comp B: P2P Sync Engine).
///
/// Holds signed Ed25519 ops waiting to be forwarded via libp2p Gossipsub.
/// Mirrors the rusqlite queue described in the V1.1 spec; this Dart-side
/// table is used until the Rust FFI bridge is in place.
class OpsQueue extends Table {
  /// UUID v4 generated locally at op creation time
  TextColumn get opId => text()();

  /// DID of the local identity that authored this op
  TextColumn get authorDid => text()();

  /// "board" | "thread" | "post" | "reaction"
  TextColumn get entityType => text()();

  /// UUID of the target entity
  TextColumn get entityId => text()();

  /// CRDT operation type: "insert" | "update" | "delete" | "crdt_merge"
  TextColumn get opType => text()();

  /// base64-encoded Yrs binary delta (CRDT payload)
  TextColumn get payload => text()();

  /// Ed25519 signature over (opId || payload), hex-encoded
  TextColumn get signature => text()();

  /// "pending" | "sent" | "synced" | "rejected"
  TextColumn get status => text().withDefault(const Constant('pending'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// null until first transmission attempt
  DateTimeColumn get sentAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {opId};
}
