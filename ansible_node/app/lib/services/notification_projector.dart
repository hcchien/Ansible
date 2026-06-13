import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';

import 'notification_preferences_controller.dart';

/// Decides whether a notification category is currently enabled.
typedef NotificationCategoryEnabled =
    Future<bool> Function(NotificationCategory category);

/// Folds already-synced data into local notifications (Phase A of the
/// notification plan).
///
/// Constitution note: this is a pure **local projection** — it only reads ops
/// and mailbox messages the device already downloaded and writes rows to the
/// local `notifications` table. Nothing here performs (or influences) any
/// server request, so the relay never learns which notifications exist or
/// which ones the user read.
class NotificationProjector {
  NotificationProjector({
    required NotificationRepository notifications,
    required String localDid,
    ThreadRepository? threadRepository,
    PostRepository? postRepository,
    ContactRepository? contactRepository,
    NotificationCategoryEnabled? isCategoryEnabled,
    DateTime Function()? now,
  }) : _notifications = notifications,
       _localDid = localDid,
       _threadRepo = threadRepository,
       _postRepo = postRepository,
       _contactRepo = contactRepository,
       _isCategoryEnabled = isCategoryEnabled,
       _now = now ?? (() => DateTime.now().toUtc());

  final NotificationRepository _notifications;
  final String _localDid;
  final ThreadRepository? _threadRepo;
  final PostRepository? _postRepo;
  final ContactRepository? _contactRepo;
  final NotificationCategoryEnabled? _isCategoryEnabled;
  final DateTime Function() _now;

  /// Folds one trusted (signature-verified) activity from an op sync pass.
  ///
  /// Emits `reply_to_post` / `reply_to_thread` when the parent post/thread
  /// author is the local DID, and `new_follower` for follow ops targeting the
  /// local DID. Self-actions never notify. Best-effort: failures must never
  /// break the sync pass.
  Future<void> onSyncedActivity(Activity activity) async {
    try {
      if (_localDid.isEmpty) return;
      // Self-actions (own replies/follows echoed back by the relay).
      if (activity.authorId == _localDid) return;
      if (activity.type.toLowerCase() != 'create') return;

      switch (activity.entityType.toLowerCase()) {
        case 'post':
          await _onPostCreated(activity);
          break;
        case 'follow':
          await _onFollowCreated(activity);
          break;
      }
    } catch (_) {
      // Notifications are best-effort; never let them break sync.
    }
  }

  /// Folds one decrypted inbound messenger message. Blocked senders (same
  /// checks the inbox applies) and self-messages never notify.
  Future<void> onMessengerMessage({
    required String senderDid,
    required String messageId,
    DateTime? receivedAt,
  }) async {
    try {
      if (_localDid.isNotEmpty && senderDid == _localDid) return;
      if (await _isSenderBlocked(senderDid)) return;
      if (!await _enabled(NotificationCategory.messenger)) return;

      final dedupKey = 'messenger:$messageId';
      await _notifications.upsertByDedupKey(
        AppNotification(
          id: dedupKey,
          type: NotificationType.messengerMessage,
          actorDid: senderDid,
          targetRef: messageId,
          conversationId: senderDid,
          createdAt: receivedAt ?? _now(),
          dedupKey: dedupKey,
        ),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _onPostCreated(Activity activity) async {
    final parentPostId = activity.payload['parentPostId'] as String?;

    // Reply to one of my posts?
    if (parentPostId != null && parentPostId.isNotEmpty) {
      final parent = await _postRepo?.getById(parentPostId);
      if (parent != null && parent.authorId == _localDid) {
        if (!await _enabled(NotificationCategory.reply)) return;
        await _emitReply(activity, NotificationType.replyToPost);
        return;
      }
    }

    // Reply in one of my threads?
    final threadId = activity.threadId;
    if (threadId == null || threadId.isEmpty) return;
    final thread = await _threadRepo?.getById(threadId);
    if (thread == null || thread.authorId != _localDid) return;
    if (!await _enabled(NotificationCategory.reply)) return;
    await _emitReply(activity, NotificationType.replyToThread);
  }

  Future<void> _emitReply(Activity activity, NotificationType type) async {
    // One reply post = one notification, whatever it was classified as, so a
    // re-synced op can never duplicate even if classification context changed.
    final dedupKey = 'reply:${activity.entityId}';
    await _notifications.upsertByDedupKey(
      AppNotification(
        id: dedupKey,
        type: type,
        actorDid: activity.authorId,
        targetRef: activity.entityId,
        boardId: activity.boardId,
        threadId: activity.threadId,
        postId: activity.entityId,
        createdAt: activity.createdAt,
        dedupKey: dedupKey,
      ),
    );
  }

  Future<void> _onFollowCreated(Activity activity) async {
    // Follow ops carry the target DID as entityId (see CrdtOpBuilder).
    if (activity.entityId != _localDid) return;
    if (!await _enabled(NotificationCategory.follow)) return;

    final dedupKey = 'follower:${activity.authorId}';
    await _notifications.upsertByDedupKey(
      AppNotification(
        id: dedupKey,
        type: NotificationType.newFollower,
        actorDid: activity.authorId,
        targetRef: activity.authorId,
        createdAt: activity.createdAt,
        dedupKey: dedupKey,
      ),
    );
  }

  /// Same blocked checks the messenger inbox / blocked-list settings use.
  Future<bool> _isSenderBlocked(String senderDid) async {
    final contacts = _contactRepo;
    if (contacts == null) return false;
    final contact = await contacts.contactForDid(senderDid);
    if (contact == null) return false;
    return contact.relationship == ContactRelationship.blocked ||
        contact.trustState == ContactTrustState.blocked ||
        contact.messengerAvailability == MessengerAvailability.blocked;
  }

  Future<bool> _enabled(NotificationCategory category) async {
    final isEnabled = _isCategoryEnabled;
    if (isEnabled == null) return true;
    return isEnabled(category);
  }
}
