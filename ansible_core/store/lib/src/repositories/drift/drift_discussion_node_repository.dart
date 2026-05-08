import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/discussion_node.dart' as entity;
import '../discussion_node_repository.dart';

class DriftDiscussionNodeRepository implements DiscussionNodeRepository {
  final db.AppDatabase _db;

  DriftDiscussionNodeRepository(this._db);

  @override
  Future<void> create(entity.DiscussionNode node) async {
    await _db
        .into(_db.discussionNodes)
        .insert(
          db.DiscussionNodesCompanion.insert(
            discussionNodeId: node.id,
            discussionId: node.discussionId,
            authorDid: node.authorDid,
            nodeType: node.nodeType,
            stance: node.stance,
            body: node.body,
            parentNodeId: Value(node.parentNodeId),
            createdAt: Value(node.createdAt),
            updatedAt: Value(node.updatedAt),
            isDeleted: Value(node.isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<entity.DiscussionNode>> listByDiscussion(
    String discussionId,
  ) async {
    final rows =
        await (_db.select(_db.discussionNodes)
              ..where((table) => table.discussionId.equals(discussionId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.createdAt),
                (table) => OrderingTerm.asc(table.discussionNodeId),
              ]))
            .get();
    return rows
        .map(
          (row) => entity.DiscussionNode(
            id: row.discussionNodeId,
            discussionId: row.discussionId,
            parentNodeId: row.parentNodeId,
            authorDid: row.authorDid,
            nodeType: row.nodeType,
            stance: row.stance,
            body: row.body,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            isDeleted: row.isDeleted,
          ),
        )
        .toList();
  }
}
