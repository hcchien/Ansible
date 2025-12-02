import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'handlers/auth_handler.dart';
import 'handlers/boards_handler.dart';
import 'handlers/threads_handler.dart';
import 'handlers/posts_handler.dart';
import 'handlers/inbox_handler.dart';
import 'handlers/sync_handler.dart';

Router createRouter({
  required BoardRepository boardRepository,
  required ThreadRepository threadRepository,
  required PostRepository postRepository,
  required BoardAclRepository boardAclRepository,
  required ActivityLogRepository activityLogRepository,
  required UserRepository userRepository,
}) {
  final router = Router();

  // 健康檢查
  router.get('/health', (Request req) async {
    return Response.ok('OK');
  });

  // API v1 namespace
  final authHandler = AuthHandler(userRepository: userRepository);
  final boardsHandler = BoardsHandler(
    boardRepository: boardRepository,
    threadRepository: threadRepository,
  );
  final threadsHandler = ThreadsHandler(
    threadRepository: threadRepository,
    postRepository: postRepository,
  );
  final postsHandler = PostsHandler(postRepository: postRepository);
  final inboxHandler = InboxHandler(
    activityLogRepository: activityLogRepository,
    boardRepository: boardRepository,
    threadRepository: threadRepository,
    postRepository: postRepository,
    boardAclRepository: boardAclRepository,
  );
  final syncHandler = SyncHandler(activityLogRepository: activityLogRepository);

  router.mount('/api/v1/auth', authHandler.router);
  router.mount('/api/v1/boards', boardsHandler.router);
  router.mount('/api/v1/threads', threadsHandler.router);
  router.mount('/api/v1/posts', postsHandler.router);
  router.mount('/api/v1/inbox', inboxHandler.router);
  router.mount('/api/v1/sync', syncHandler.router);

  return router;
}
