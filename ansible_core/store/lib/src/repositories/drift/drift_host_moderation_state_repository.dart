import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/host_moderation_state.dart';
import '../host_moderation_state_repository.dart';

class DriftHostModerationStateRepository
    implements HostModerationStateRepository {
  final AppDatabase _db;

  DriftHostModerationStateRepository(this._db);

  @override
  Future<List<HostModerationState>> replaceForBoard(
    String localBoardId,
    List<HostModerationState> entries,
  ) async {
    return _db.transaction(() async {
      final previousKeys = (await listForBoard(
        localBoardId,
      )).map((entry) => entry.diffKey).toSet();

      await (_db.delete(_db.hostModerationStates)
            ..where((t) => t.localBoardId.equals(localBoardId)))
          .go();

      // De-duplicate on the primary key (board, kind, ref) defensively; the
      // host serves at most one action per target.
      final seen = <String>{};
      final applied = <HostModerationState>[];
      for (final entry in entries) {
        if (!seen.add('${entry.targetKind}:${entry.targetRef}')) continue;
        applied.add(entry);
        await _db
            .into(_db.hostModerationStates)
            .insert(
              HostModerationStatesCompanion.insert(
                localBoardId: localBoardId,
                targetKind: entry.targetKind,
                targetRef: entry.targetRef,
                action: entry.action,
                reasonCode: entry.reasonCode,
                updatedAt: entry.updatedAt,
              ),
            );
      }

      return applied
          .where((entry) => !previousKeys.contains(entry.diffKey))
          .toList();
    });
  }

  @override
  Future<List<HostModerationState>> listForBoard(String localBoardId) async {
    final rows =
        await (_db.select(_db.hostModerationStates)
              ..where((t) => t.localBoardId.equals(localBoardId)))
            .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<HostModerationState?> entryFor(
    String targetKind,
    String targetRef,
  ) async {
    final row =
        await (_db.select(_db.hostModerationStates)..where(
              (t) =>
                  t.targetKind.equals(targetKind) &
                  t.targetRef.equals(targetRef),
            ))
            .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  HostModerationState _toEntity(HostModerationStateRow row) {
    return HostModerationState(
      localBoardId: row.localBoardId,
      targetKind: row.targetKind,
      targetRef: row.targetRef,
      action: row.action,
      reasonCode: row.reasonCode,
      updatedAt: row.updatedAt,
    );
  }
}
