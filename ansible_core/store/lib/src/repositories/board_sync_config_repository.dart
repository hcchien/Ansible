import '../entities/board_sync_config.dart';

abstract class BoardSyncConfigRepository {
  Future<BoardSyncConfig?> getById(String id);
  Future<BoardSyncConfig?> getByRemoteAndBoard(String remoteNodeId, String boardId);
  Future<List<BoardSyncConfig>> listByRemote(String remoteNodeId);
  Future<List<String>> getEnabledBoardIds(String remoteNodeId);
  Future<void> create(BoardSyncConfig config);
  Future<void> update(BoardSyncConfig config);
  Future<void> delete(String id);
  Future<void> toggleSync(String remoteNodeId, String boardId, bool enabled);
}
