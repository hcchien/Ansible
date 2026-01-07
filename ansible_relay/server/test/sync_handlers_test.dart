import 'dart:convert';

import 'package:ansible_relay/src/handlers/inbox_handler.dart';
import 'package:ansible_relay/src/handlers/sync_handler.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Inbox & Sync handlers', () {
    late AppDatabase db;
    late BoardRepository boardRepository;
    late ThreadRepository threadRepository;
    late PostRepository postRepository;
    late BoardAclRepository boardAclRepository;
    late ActivityLogRepository activityLogRepository;
    late UserRepository userRepository;
    late InboxHandler inboxHandler;
    late SyncHandler syncHandler;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      boardRepository = DriftBoardRepository(db);
      threadRepository = DriftThreadRepository(db);
      postRepository = DriftPostRepository(db);
      boardAclRepository = DriftBoardAclRepository(db);
      activityLogRepository = DriftActivityLogRepository(db);
      userRepository = DriftUserRepository(db);

      inboxHandler = InboxHandler(
        activityLogRepository: activityLogRepository,
        boardRepository: boardRepository,
        threadRepository: threadRepository,
        postRepository: postRepository,
        boardAclRepository: boardAclRepository,
      );
      syncHandler = SyncHandler(activityLogRepository: activityLogRepository);

      final now = DateTime.now().toUtc();
      await userRepository.create(User(
        userId: 'user-1',
        username: 'user-1',
        passwordHash: 'pw',
        displayName: 'User 1',
        createdAt: now,
        updatedAt: now,
      ));

      await boardRepository.create(Board(
        id: 'board-1',
        slug: 'board-1',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ));
      await boardAclRepository.setAcl(BoardAcl(
        boardId: 'board-1',
        userId: 'user-1',
        canRead: true,
        canWrite: true,
        isAdmin: true,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    Future<Response> _callInbox(
      List<Map<String, dynamic>> activities, {
      String userId = 'user-1',
    }) {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'activities': activities}),
      ).change(context: {'userId': userId});
      return inboxHandler.router.call(request);
    }

    Response _callDelta({required int cursor, int limit = 100}) {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/delta?cursor=$cursor&limit=$limit'),
      );
      return syncHandler.router.call(request);
    }

    Map<String, dynamic> _createThreadActivity({
      required String activityId,
      required String threadId,
      String boardId = 'board-1',
      String authorId = 'user-1',
      DateTime? createdAt,
      String title = 'Hello',
    }) {
      final ts = (createdAt ?? DateTime.now().toUtc()).toIso8601String();
      return {
        'activityId': activityId,
        'originNodeId': 'node-a',
        'type': 'CreateThread',
        'entityType': 'thread',
        'entityId': threadId,
        'boardId': boardId,
        'threadId': threadId,
        'authorId': authorId,
        'createdAt': ts,
        'payload': {
          'id': threadId,
          'boardId': boardId,
          'authorId': authorId,
          'title': title,
          'createdAt': ts,
          'updatedAt': ts,
        },
      };
    }

    Map<String, dynamic> _createPostActivity({
      required String activityId,
      required String postId,
      required String threadId,
      String boardId = 'board-1',
      String authorId = 'user-1',
      DateTime? createdAt,
      String content = 'Hello world',
    }) {
      final ts = (createdAt ?? DateTime.now().toUtc()).toIso8601String();
      return {
        'activityId': activityId,
        'originNodeId': 'node-a',
        'type': 'CreatePost',
        'entityType': 'post',
        'entityId': postId,
        'boardId': boardId,
        'threadId': threadId,
        'authorId': authorId,
        'createdAt': ts,
        'payload': {
          'id': postId,
          'threadId': threadId,
          'boardId': boardId,
          'authorId': authorId,
          'content': content,
          'createdAt': ts,
          'updatedAt': ts,
          'lastEditAt': ts,
        },
      };
    }

    test('accepts activities, applies domain, and logs them', () async {
      final threadActivity =
          _createThreadActivity(activityId: 'act-thread-1', threadId: 'thread-1');
      final postActivity = _createPostActivity(
        activityId: 'act-post-1',
        postId: 'post-1',
        threadId: 'thread-1',
      );

      final response = await _callInbox([threadActivity, postActivity]);
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final results = body['results'] as List;
      expect(results.map((r) => r['status']), everyElement('accepted'));

      final logs = await activityLogRepository.list(limit: 10);
      expect(logs, hasLength(2));
      expect(logs[0].activityId, 'act-thread-1');

      final storedThread = await threadRepository.getById('thread-1');
      final storedPost = await postRepository.getById('post-1');
      expect(storedThread, isNotNull);
      expect(storedPost?.content, 'Hello world');
    });

    test('deduplicates by activityId', () async {
      final activity = _createThreadActivity(
        activityId: 'act-dup-1',
        threadId: 'thread-dup',
      );

      final first = await _callInbox([activity]);
      final firstBody = jsonDecode(await first.readAsString()) as Map<String, dynamic>;
      final firstLogId = (firstBody['results'] as List).first['logId'];

      final second = await _callInbox([activity]);
      final secondBody = jsonDecode(await second.readAsString()) as Map<String, dynamic>;
      final secondResult = (secondBody['results'] as List).first;
      expect(secondResult['status'], 'duplicate');
      expect(secondResult['logId'], firstLogId);
    });

    test('rejects when writer lacks board ACL', () async {
      final now = DateTime.now().toUtc();
      await userRepository.create(User(
        userId: 'user-2',
        username: 'user-2',
        passwordHash: 'pw',
        displayName: 'User 2',
        createdAt: now,
        updatedAt: now,
      ));

      final activity = _createPostActivity(
        activityId: 'act-forbidden-1',
        postId: 'post-no-acl',
        threadId: 'thread-1',
        authorId: 'user-2',
      );

      final response = await _callInbox([activity], userId: 'user-2');
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final result = (body['results'] as List).first;
      expect(result['status'], 'forbidden');
      expect(result['error'], 'BOARD_WRITE_DENIED');
    });

    test('sync delta paginates with cursor', () async {
      final threadActivity =
          _createThreadActivity(activityId: 'act-thread-2', threadId: 'thread-2');
      final postActivity = _createPostActivity(
        activityId: 'act-post-2',
        postId: 'post-2',
        threadId: 'thread-2',
      );
      await _callInbox([threadActivity, postActivity]);

      final first = _callDelta(cursor: 0, limit: 1);
      expect(first.statusCode, 200);
      final firstBody = jsonDecode(await first.readAsString()) as Map<String, dynamic>;
      expect(firstBody['activities'], hasLength(1));
      expect(firstBody['hasMore'], isTrue);
      final nextCursor = firstBody['nextCursor'] as int;

      final second = _callDelta(cursor: nextCursor, limit: 5);
      expect(second.statusCode, 200);
      final secondBody = jsonDecode(await second.readAsString()) as Map<String, dynamic>;
      expect(secondBody['activities'], hasLength(1));
      expect(secondBody['hasMore'], isFalse);
      expect(secondBody['nextCursor'], isA<int>());
    });

    test('invalid cursor returns validation error', () async {
      final res = _callDelta(cursor: -1, limit: 1);
      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['error']['code'], 'VALIDATION_ERROR');
    });
  });
}







