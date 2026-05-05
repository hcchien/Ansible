import '../../entities/board_sync_config.dart';
import '../board_sync_config_repository.dart';

class InMemoryBoardSyncConfigRepository implements BoardSyncConfigRepository {
  final Map<String, BoardSyncConfig> _configs = {};

  @override
  Future<void> create(BoardSyncConfig config) async {
    _configs[config.id] = config;
  }

  @override
  Future<BoardSyncConfig?> getById(String id) async {
    return _configs[id];
  }

  @override
  Future<BoardSyncConfig?> getByRemoteAndBoard(
    String remoteNodeId,
    String boardId,
  ) async {
    for (final config in _configs.values) {
      if (config.remoteNodeId == remoteNodeId && config.boardId == boardId) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<List<BoardSyncConfig>> listByRemote(String remoteNodeId) async {
    return _configs.values
        .where((config) => config.remoteNodeId == remoteNodeId)
        .toList();
  }

  @override
  Future<List<BoardSyncConfig>> listEnabledByRemote(String remoteNodeId) async {
    return _configs.values
        .where(
          (config) => config.remoteNodeId == remoteNodeId && config.syncEnabled,
        )
        .toList();
  }

  @override
  Future<List<String>> getEnabledBoardIds(String remoteNodeId) async {
    final configs = await listEnabledByRemote(remoteNodeId);
    return configs.map((config) => config.boardId).toList();
  }

  @override
  Future<void> update(BoardSyncConfig config) async {
    _configs[config.id] = config;
  }

  @override
  Future<void> delete(String id) async {
    _configs.remove(id);
  }

  @override
  Future<void> toggleSync(
    String remoteNodeId,
    String boardId,
    bool enabled,
  ) async {
    final existing = await getByRemoteAndBoard(remoteNodeId, boardId);
    final now = DateTime.now().toUtc();
    if (existing == null) {
      await create(
        BoardSyncConfig(
          id: '${remoteNodeId}_$boardId',
          remoteNodeId: remoteNodeId,
          boardId: boardId,
          syncEnabled: enabled,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return;
    }

    await update(existing.copyWith(syncEnabled: enabled, updatedAt: now));
  }
}
