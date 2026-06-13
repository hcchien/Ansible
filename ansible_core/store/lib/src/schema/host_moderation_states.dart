import 'package:drift/drift.dart';

/// Per-board moderation state synced from the board's Forum Host (removed
/// posts, locked threads), reason-coded so the affected author can always see
/// why (constitution Base Rule 6). Snapshot-applied: each sync replaces a
/// board's rows with the host's authoritative state.
@DataClassName('HostModerationStateRow')
class HostModerationStates extends Table {
  /// Local board id (the hosted board's projection on this device).
  TextColumn get localBoardId => text()();

  /// `"post"` | `"thread"`.
  TextColumn get targetKind => text()();

  /// Op entity id of the moderated post/thread.
  TextColumn get targetRef => text()();

  /// `"removed"` | `"locked"`.
  TextColumn get action => text()();

  /// Reason code from the fixed enum (spam, harassment, ...).
  TextColumn get reasonCode => text()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localBoardId, targetKind, targetRef};
}
