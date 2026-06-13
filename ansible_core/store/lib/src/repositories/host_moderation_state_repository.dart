import '../entities/host_moderation_state.dart';

abstract class HostModerationStateRepository {
  /// Snapshot-applies the host's authoritative moderation state for one
  /// board: deletes the board's existing rows and inserts [entries].
  ///
  /// Returns the entries that are **new** relative to the previous snapshot
  /// (diffed by target kind + target ref + action), so callers can react to
  /// fresh moderation outcomes (e.g. notify the affected local author)
  /// without re-firing on every sync pass.
  Future<List<HostModerationState>> replaceForBoard(
    String localBoardId,
    List<HostModerationState> entries,
  );

  /// All moderation entries for a local board.
  Future<List<HostModerationState>> listForBoard(String localBoardId);

  /// The entry for a specific target, across boards (target refs are op
  /// entity ids, unique network-wide). Null when the target is unmoderated.
  Future<HostModerationState?> entryFor(String targetKind, String targetRef);
}
