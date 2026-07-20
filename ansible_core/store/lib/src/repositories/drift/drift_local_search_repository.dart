import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/local_search_result.dart';
import '../local_search_repository.dart';

class DriftLocalSearchRepository implements LocalSearchRepository {
  DriftLocalSearchRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<LocalSearchResult>> search(
    String query, {
    LocalSearchScope scope = LocalSearchScope.all,
    int limit = 60,
  }) async {
    final needle = query.trim();
    final perKindLimit = limit.clamp(1, 100);
    final results = <LocalSearchResult>[];

    if (scope != LocalSearchScope.private) {
      final boards = _db.select(_db.boards)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(perKindLimit);
      if (needle.isNotEmpty) {
        boards.where(
          (t) => t.title.contains(needle) | t.description.contains(needle),
        );
      }
      results.addAll(
        (await boards.get()).map(
          (row) => LocalSearchResult(
            kind: LocalSearchKind.board,
            entityId: row.boardId,
            boardId: row.boardId,
            title: row.title,
            body: row.description ?? '',
            updatedAt: row.updatedAt,
            visibility: 'public',
          ),
        ),
      );

      final threads = _db.select(_db.threads)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(perKindLimit);
      if (needle.isNotEmpty) {
        threads.where((t) => t.title.contains(needle));
      }
      results.addAll(
        (await threads.get()).map(
          (row) => LocalSearchResult(
            kind: LocalSearchKind.thread,
            entityId: row.threadId,
            boardId: row.boardId,
            threadId: row.threadId,
            authorDid: row.authorId,
            title: row.title,
            body: '',
            updatedAt: row.updatedAt,
            visibility: 'public',
          ),
        ),
      );

      final posts = _db.select(_db.posts)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(perKindLimit);
      if (needle.isNotEmpty) {
        posts.where((t) => t.content.contains(needle));
      }
      results.addAll(
        (await posts.get()).map(
          (row) => LocalSearchResult(
            kind: LocalSearchKind.post,
            entityId: row.postId,
            boardId: row.boardId,
            threadId: row.threadId,
            authorDid: row.authorId,
            title: '',
            body: row.content,
            updatedAt: row.updatedAt,
            visibility: 'public',
          ),
        ),
      );
    }

    final content = _db.select(_db.contentItems)
      ..where((t) => t.isDeleted.equals(false))
      ..where((t) => t.mode.isIn(['note', 'murmur']))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(perKindLimit);
    switch (scope) {
      case LocalSearchScope.private:
        content.where((t) => t.visibility.equals('private'));
      case LocalSearchScope.public:
        content.where((t) => t.visibility.equals('public'));
      case LocalSearchScope.circle:
        content.where((t) => t.visibility.equals('unlisted'));
      case LocalSearchScope.all:
        break;
    }
    if (needle.isNotEmpty) {
      content.where((t) => t.title.contains(needle) | t.body.contains(needle));
    }
    results.addAll(
      (await content.get()).map(
        (row) => LocalSearchResult(
          kind: row.mode == 'note'
              ? LocalSearchKind.note
              : LocalSearchKind.murmur,
          entityId: row.contentItemId,
          authorDid: row.authorDid,
          title: row.title ?? '',
          body: row.body,
          updatedAt: row.updatedAt,
          visibility: row.visibility,
          localOnly: row.localOnly,
        ),
      ),
    );

    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results.take(limit).toList(growable: false);
  }
}
