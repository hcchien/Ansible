import '../entities/board_acl.dart';

abstract class BoardAclRepository {
  Future<void> setAcl(BoardAcl acl);
  Future<BoardAcl?> getAcl(String boardId, String userId);
  Future<List<BoardAcl>> getByBoardId(String boardId);
  Future<List<BoardAcl>> getByUserId(String userId);
  Future<void> deleteAcl(String boardId, String userId);
}
