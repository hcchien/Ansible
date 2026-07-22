import 'package:ansible_store/ansible_store.dart';

/// Reconstructs the local notification projection from data already present
/// in SQLite. This is intentionally idempotent: stable dedup keys preserve
/// read state and make repeated rebuilds harmless.
///
/// No network request is made and no notification/read metadata leaves the
/// device. Live sync continues to use [NotificationProjector]; this service
/// covers data that existed before notification projection was enabled.
class LocalNotificationRebuilder {
  const LocalNotificationRebuilder({
    required NotificationRepository notifications,
    required ThreadRepository threads,
    required PostRepository posts,
    required MessengerRepository messenger,
    required String localDid,
  }) : _notifications = notifications,
       _threads = threads,
       _posts = posts,
       _messenger = messenger,
       _localDid = localDid;

  final NotificationRepository _notifications;
  final ThreadRepository _threads;
  final PostRepository _posts;
  final MessengerRepository _messenger;
  final String _localDid;

  Future<void> rebuild() async {
    if (_localDid.isEmpty) return;
    await _rebuildReplies();
    await _rebuildMessenger();
  }

  Future<void> _rebuildReplies() async {
    final posts = await _posts.list();
    final postsById = {for (final post in posts) post.id: post};
    final threadsById = <String, Thread?>{};

    for (final post in posts) {
      if (post.isDeleted ||
          !post.signatureVerified ||
          post.authorId == _localDid) {
        continue;
      }

      NotificationType? type;
      final parentId = post.parentPostId;
      if (parentId != null && postsById[parentId]?.authorId == _localDid) {
        type = NotificationType.replyToPost;
      } else {
        final thread = threadsById.containsKey(post.threadId)
            ? threadsById[post.threadId]
            : await _threads.getById(post.threadId);
        threadsById[post.threadId] = thread;
        if (thread?.authorId == _localDid) {
          type = NotificationType.replyToThread;
        }
      }
      if (type == null) continue;

      final dedupKey = 'reply:${post.id}';
      await _notifications.upsertByDedupKey(
        AppNotification(
          id: dedupKey,
          type: type,
          actorDid: post.authorId,
          targetRef: post.id,
          boardId: post.boardId,
          threadId: post.threadId,
          postId: post.id,
          createdAt: post.createdAt,
          dedupKey: dedupKey,
        ),
      );
    }
  }

  Future<void> _rebuildMessenger() async {
    for (final conversation in await _messenger.conversationList()) {
      for (final message in await _messenger.messagesForConversation(
        conversation.conversationId,
      )) {
        if (message.direction != MessengerMessageDirection.inbound ||
            message.status == MessengerMessageStatus.decryptFailed) {
          continue;
        }
        final dedupKey = 'messenger:${message.messageId}';
        await _notifications.upsertByDedupKey(
          AppNotification(
            id: dedupKey,
            type: NotificationType.messengerMessage,
            actorDid: conversation.peerDid,
            targetRef: message.messageId,
            conversationId: conversation.conversationId,
            createdAt: message.createdAt,
            dedupKey: dedupKey,
          ),
        );
      }
    }
  }
}
