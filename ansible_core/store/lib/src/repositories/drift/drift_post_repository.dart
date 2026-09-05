import 'dart:convert';

import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/post.dart' as entity;
import '../post_repository.dart';

class DriftPostRepository implements PostRepository {
  final AppDatabase _db;

  DriftPostRepository(this._db);

  @override
  Future<void> create(entity.Post post) async {
    await _db
        .into(_db.posts)
        .insert(
          PostsCompanion.insert(
            postId: post.id,
            threadId: post.threadId,
            boardId: post.boardId,
            authorId: post.authorId,
            content: post.content,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            lastEditAt: post.lastEditAt,
            parentPostId: Value(post.parentPostId),
            isDeleted: Value(post.isDeleted),
            signatureVerified: Value(post.signatureVerified),
            mentionsJson: Value(
              jsonEncode(
                post.mentions.map((mention) => mention.toJson()).toList(),
              ),
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.Post?> getById(String id) async {
    final row = await (_db.select(
      _db.posts,
    )..where((t) => t.postId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.Post>> list({String? threadId}) async {
    final query = _db.select(_db.posts);
    if (threadId != null) {
      query.where((t) => t.threadId.equals(threadId));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<void> update(entity.Post post) async {
    await (_db.update(_db.posts)..where((t) => t.postId.equals(post.id))).write(
      PostsCompanion(
        threadId: Value(post.threadId),
        boardId: Value(post.boardId),
        authorId: Value(post.authorId),
        content: Value(post.content),
        updatedAt: Value(post.updatedAt),
        lastEditAt: Value(post.lastEditAt),
        parentPostId: Value(post.parentPostId),
        isDeleted: Value(post.isDeleted),
        signatureVerified: Value(post.signatureVerified),
        mentionsJson: Value(
          jsonEncode(post.mentions.map((mention) => mention.toJson()).toList()),
        ),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    // Soft delete
    await (_db.update(_db.posts)..where((t) => t.postId.equals(id))).write(
      PostsCompanion(isDeleted: Value(true), updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<int> deleteByBoardOlderThan(String boardId, DateTime cutoff) async {
    final expiredRows =
        await (_db.select(_db.posts)..where(
              (t) =>
                  t.boardId.equals(boardId) &
                  t.createdAt.isSmallerThanValue(cutoff),
            ))
            .get();
    final expiredIds = expiredRows.map((row) => row.postId).toList();
    if (expiredIds.isEmpty) {
      return 0;
    }

    await (_db.update(_db.posts)..where((t) => t.parentPostId.isIn(expiredIds)))
        .write(const PostsCompanion(parentPostId: Value(null)));

    return (_db.delete(
      _db.posts,
    )..where((t) => t.postId.isIn(expiredIds))).go();
  }

  entity.Post _mapRowToEntity(Post row) {
    return entity.Post(
      id: row.postId,
      threadId: row.threadId,
      boardId: row.boardId,
      authorId: row.authorId,
      content: row.content,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastEditAt: row.lastEditAt,
      parentPostId: row.parentPostId,
      isDeleted: row.isDeleted,
      signatureVerified: row.signatureVerified,
      mentions: _decodeMentions(row.mentionsJson),
    );
  }

  List<entity.PostMention> _decodeMentions(String value) {
    try {
      return (jsonDecode(value) as List)
          .whereType<Map>()
          .map(
            (raw) =>
                entity.PostMention.fromJson(Map<String, dynamic>.from(raw)),
          )
          .where(
            (mention) =>
                mention.did.startsWith('did:') && mention.token.isNotEmpty,
          )
          .take(10)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
