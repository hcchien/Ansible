import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/moderation_copy.dart';
import '../services/messenger_sync_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'messenger_thread_screen.dart';
import 'posts_view_screen.dart';
import 'user_profile_screen.dart';

/// In-app notification feed (Phase A): a pure read of the local
/// `notifications` table. Tapping a row marks it read and navigates to the
/// thread / profile / conversation it refers to.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.db,
    required this.did,
    this.repository,
    this.messengerService,
    this.embedded = false,
  });

  /// When true the screen is hosted as a bottom-nav tab (not a pushed route),
  /// so it omits the back affordance — the nav switches destinations.
  final bool embedded;

  final AppDatabase db;

  /// The local user's DID (notification recipient).
  final String did;

  /// Override for tests; defaults to the Drift repository over [db].
  final NotificationRepository? repository;

  /// Needed to open messenger conversations; omitted in contexts (or tests)
  /// without a messenger stack, where tapping still marks the row read.
  final MessengerSyncService? messengerService;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationRepository _repo;
  late final DriftThreadRepository _threadRepo;
  late final DriftContactRepository _contactRepo;
  late final DriftHostModerationStateRepository _moderationRepo;

  List<AppNotification> _notifications = const [];
  Map<String, ContactRecord> _actorContacts = const {};

  /// notification id → moderation reason code, looked up from the synced
  /// host moderation overlay (the notification row itself carries no reason).
  Map<String, String> _moderationReasons = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? DriftNotificationRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _contactRepo = DriftContactRepository(widget.db);
    _moderationRepo = DriftHostModerationStateRepository(widget.db);
    _load();
  }

  Future<void> _load() async {
    final notifications = await _repo.list();
    final contacts = <String, ContactRecord>{};
    for (final did in notifications.map((n) => n.actorDid).toSet()) {
      if (did.isEmpty) continue;
      final contact = await _contactRepo.contactForDid(did);
      if (contact != null) contacts[did] = contact;
    }
    final moderationReasons = <String, String>{};
    for (final notification in notifications.where(
      (n) => n.type == NotificationType.moderationOutcome,
    )) {
      final targetKind = notification.postId != null
          ? HostModerationState.targetKindPost
          : HostModerationState.targetKindThread;
      final entry = await _moderationRepo.entryFor(
        targetKind,
        notification.targetRef,
      );
      if (entry != null) moderationReasons[notification.id] = entry.reasonCode;
    }
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _actorContacts = contacts;
      _moderationReasons = moderationReasons;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await _repo.markAllRead();
    await _load();
  }

  Future<void> _openNotification(AppNotification notification) async {
    await _repo.markRead(notification.id);
    if (!mounted) return;
    switch (notification.type) {
      case NotificationType.replyToThread:
      case NotificationType.replyToPost:
        await _openThread(notification);
        break;
      case NotificationType.newFollower:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              db: widget.db,
              followerDid: widget.did,
              did: notification.actorDid,
              displayName: _actorContacts[notification.actorDid]?.label,
            ),
          ),
        );
        break;
      case NotificationType.messengerMessage:
        await _openConversation(notification);
        break;
      case NotificationType.moderationOutcome:
        // Navigate to the thread context, like replies do.
        await _openThread(notification);
        break;
    }
    if (mounted) await _load();
  }

  Future<void> _openThread(AppNotification notification) async {
    final threadId = notification.threadId;
    final thread = threadId == null
        ? null
        : await _threadRepo.getById(threadId);
    if (!mounted) return;
    if (thread == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '找不到這則討論串，可能已被刪除',
              en: 'Thread not found; it may have been deleted',
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PostsViewScreen(db: widget.db, thread: thread, authorDid: widget.did),
      ),
    );
  }

  Future<void> _openConversation(AppNotification notification) async {
    final messengerService = widget.messengerService;
    if (messengerService == null) return;
    final conversationId = notification.conversationId ?? notification.actorDid;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerThreadScreen(
          conversationId: conversationId,
          senderDid: widget.did,
          messengerService: messengerService,
          contact: _actorContacts[notification.actorDid],
        ),
      ),
    );
  }

  String _actorLabel(BuildContext context, AppNotification notification) {
    if (notification.type == NotificationType.moderationOutcome) {
      // Public moderation state carries no moderator DID by design.
      return context.uiCopy(zh: '板務', en: 'Board moderators');
    }
    final contact = _actorContacts[notification.actorDid];
    if (contact != null) return contact.label;
    return _shortDid(notification.actorDid);
  }

  static String _shortDid(String did) {
    if (did.length <= 20) return did;
    return '${did.substring(0, 14)}…${did.substring(did.length - 4)}';
  }

  String _typeLabel(BuildContext context, AppNotification notification) {
    return switch (notification.type) {
      NotificationType.replyToThread => context.uiCopy(
        zh: '回覆了你的討論串',
        en: 'replied to your thread',
      ),
      NotificationType.replyToPost => context.uiCopy(
        zh: '回覆了你的留言',
        en: 'replied to your post',
      ),
      NotificationType.newFollower => context.uiCopy(
        zh: '開始追蹤你',
        en: 'started following you',
      ),
      NotificationType.messengerMessage => context.uiCopy(
        zh: '傳來一則私訊',
        en: 'sent you a message',
      ),
      NotificationType.moderationOutcome => _moderationOutcomeLabel(
        context,
        notification,
      ),
    };
  }

  String _moderationOutcomeLabel(
    BuildContext context,
    AppNotification notification,
  ) {
    final reasonCode = _moderationReasons[notification.id];
    if (reasonCode == null) {
      return context.uiCopy(
        zh: '你的內容已被板務處理',
        en: 'Your content was moderated',
      );
    }
    final reason = moderationReasonLabel(context, reasonCode);
    return context.uiCopy(
      zh: '你的內容已被板務處理（$reason）',
      en: 'Your content was moderated ($reason)',
    );
  }

  String _typeGlyph(NotificationType type) {
    return switch (type) {
      NotificationType.replyToThread ||
      NotificationType.replyToPost => '↩',
      NotificationType.newFollower => '◎',
      NotificationType.messengerMessage => '✉',
      NotificationType.moderationOutcome => '⚑',
    };
  }

  String _relativeTime(BuildContext context, DateTime createdAt) {
    final l10n = context.l10n;
    final diff = DateTime.now().difference(createdAt.toLocal());
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
    return l10n.daysAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !n.isRead);
    return AnsibleScreenScaffold(
      title: 'NOTIFICATIONS',
      leadingLabel: widget.embedded
          ? ''
          : context.uiCopy(zh: '← 返回', en: '← Back'),
      trailing: hasUnread
          ? TextButton(
              key: const Key('notifications_mark_all_read'),
              onPressed: _markAllRead,
              child: Text(
                context.uiCopy(zh: '全部已讀', en: 'Mark all read'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            )
          : null,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _notifications.isEmpty
          ? _EmptyNotifications()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                thickness: 0.5,
                color: AnsibleDesign.ruleSoft,
              ),
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                return _NotificationRow(
                  key: Key('notification_row_${notification.id}'),
                  glyph: _typeGlyph(notification.type),
                  actorLabel: _actorLabel(context, notification),
                  typeLabel: _typeLabel(context, notification),
                  timeLabel: _relativeTime(context, notification.createdAt),
                  unread: !notification.isRead,
                  onTap: () => _openNotification(notification),
                );
              },
            ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.glyph,
    required this.actorLabel,
    required this.typeLabel,
    required this.timeLabel,
    required this.unread,
    required this.onTap,
  });

  final String glyph;
  final String actorLabel;
  final String typeLabel;
  final String timeLabel;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            AnsibleGlyphBox(glyph: glyph),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actorLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      color: AnsibleDesign.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: unread
                          ? AnsibleDesign.ink
                          : AnsibleDesign.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeLabel,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                if (unread) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: const Key('notification_unread_dot'),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AnsibleDesign.ochre,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          decoration: BoxDecoration(
            color: AnsibleDesign.paperElev,
            border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const AnsibleGlyphBox(glyph: '◇'),
              const SizedBox(height: 14),
              Text(
                context.uiCopy(zh: '目前沒有通知', en: 'No notifications yet'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.uiCopy(
                  zh: '有人回覆你、追蹤你或傳訊息給你時，會出現在這裡。',
                  en: 'When someone replies to you, follows you, or sends '
                      'you a message, it shows up here.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
