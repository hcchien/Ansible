import 'package:ansible_store/ansible_store.dart';
import 'notification_preferences_controller.dart';

/// Reconstructs the local notification projection from data already present
/// in SQLite. This is intentionally idempotent: stable dedup keys preserve
/// read state and make repeated rebuilds harmless.
///
/// No network request is made and no notification/read metadata leaves the
/// device. Live sync continues to use [NotificationProjector]; this service
/// covers data that existed before notification projection was enabled.
class LocalNotificationRebuilder {
  LocalNotificationRebuilder({
    required NotificationRepository notifications,
    required ThreadRepository threads,
    required PostRepository posts,
    required MessengerRepository messenger,
    ContentItemRepository? contents,
    Future<bool> Function(NotificationCategory)? isCategoryEnabled,
    required String localDid,
    Iterable<String> localDidAliases = const [],
  }) : _notifications = notifications,
       _threads = threads,
       _posts = posts,
       _messenger = messenger,
       _contents = contents,
       _isCategoryEnabled = isCategoryEnabled,
       _localDids = {
         localDid,
         ...localDidAliases,
       }.map((did) => did.trim()).where((did) => did.isNotEmpty).toSet();

  final NotificationRepository _notifications;
  final ThreadRepository _threads;
  final PostRepository _posts;
  final MessengerRepository _messenger;
  final ContentItemRepository? _contents;
  final Future<bool> Function(NotificationCategory)? _isCategoryEnabled;
  final Set<String> _localDids;

  Future<void> rebuild() async {
    if (_localDids.isEmpty) return;
    if (await _isCategoryEnabled?.call(NotificationCategory.reply) ?? true) {
      await _rebuildReplies();
    }
    if (await _isCategoryEnabled?.call(NotificationCategory.messenger) ??
        true) {
      await _rebuildMessenger();
    }
  }

  Future<void> _rebuildReplies() async {
    final posts = await _posts.list();
    final postsById = {for (final post in posts) post.id: post};
    final threadsById = <String, Thread?>{};

    for (final post in posts) {
      if (post.isDeleted ||
          !post.signatureVerified ||
          _localDids.contains(post.authorId)) {
        continue;
      }

      NotificationType? type;
      final parentId = post.parentPostId;
      if (parentId != null &&
          _localDids.contains(postsById[parentId]?.authorId)) {
        type = NotificationType.replyToPost;
      } else {
        final thread = threadsById.containsKey(post.threadId)
            ? threadsById[post.threadId]
            : await _threads.getById(post.threadId);
        threadsById[post.threadId] = thread;
        final content = await _contents?.getById(post.threadId);
        final participated = posts.any(
          (own) =>
              own.threadId == post.threadId &&
              !own.isDeleted &&
              _localDids.contains(own.authorId) &&
              own.createdAt.isBefore(post.createdAt),
        );
        if (_localDids.contains(thread?.authorId) ||
            (content != null &&
                !content.isDeleted &&
                _localDids.contains(content.authorDid)) ||
            participated) {
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
