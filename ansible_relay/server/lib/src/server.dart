import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'middleware.dart';
import 'router.dart';

/// For embedding or tests you can use this.
Future<void> Function(HttpRequest) createAnsibleRelayHandler({AppDatabase? database}) {
  final db = database ?? AppDatabase();

  final boardRepository = DriftBoardRepository(db);
  final threadRepository = DriftThreadRepository(db);
  final postRepository = DriftPostRepository(db);
  final boardAclRepository = DriftBoardAclRepository(db);
  final activityLogRepository = DriftActivityLogRepository(db);
  final userRepository = DriftUserRepository(db);

  final router = createRouter(
    boardRepository: boardRepository,
    threadRepository: threadRepository,
    postRepository: postRepository,
    boardAclRepository: boardAclRepository,
    activityLogRepository: activityLogRepository,
    userRepository: userRepository,
  );

  final pipeline = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(jsonContentTypeMiddleware())
      .addMiddleware(corsMiddleware())
      .addMiddleware(authMiddleware())
      .addHandler(router);

  return (HttpRequest ioRequest) {
    return shelf_io.handleRequest(ioRequest, pipeline);
  };
}
