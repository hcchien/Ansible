import 'package:ansible_store/ansible_store.dart';

import 'forum_host_client.dart';
import 'notification_projector.dart';

/// Pulls each subscribed hosted board's public, reason-coded moderation
/// state from its Forum Host and snapshot-applies it locally
/// (`host_moderation_states`), so removed-post tombstones and locked-thread
/// banners render in the app.
///
/// Constitution notes (Base Rules 6/7):
/// - The state is the **host's projection** only; applying it never touches
///   the author's local content rows.
/// - The snapshot diff drives `moderation_outcome` notifications for targets
///   the local user authored — the author must see the action and why. A
///   host owner moderating their own content still notifies.
///
/// Failure-tolerant by contract: a fetch/apply error on one board never
/// breaks the others, and [syncForNode] never throws into the sync pass.
class HostModerationSyncService {
  HostModerationSyncService({
    required HostModerationStateRepository moderationRepo,
    required HostedBoardRepository hostedBoardRepo,
    ThreadRepository? threadRepo,
    PostRepository? postRepo,
    NotificationProjector? notificationProjector,
    String? localDid,
    ForumHostClient Function(String baseUrl)? clientFactory,
    DateTime Function()? now,
  }) : _moderationRepo = moderationRepo,
       _hostedBoardRepo = hostedBoardRepo,
       _threadRepo = threadRepo,
       _postRepo = postRepo,
       _notificationProjector = notificationProjector,
       _localDid = localDid,
       _clientFactory =
           clientFactory ?? ((baseUrl) => ForumHostClient(baseUrl: baseUrl)),
       _now = now ?? (() => DateTime.now().toUtc());

  final HostModerationStateRepository _moderationRepo;
  final HostedBoardRepository _hostedBoardRepo;
  final ThreadRepository? _threadRepo;
  final PostRepository? _postRepo;
  final NotificationProjector? _notificationProjector;
  final String? _localDid;
  final ForumHostClient Function(String baseUrl) _clientFactory;
  final DateTime Function() _now;

  /// Refreshes moderation state for every enabled hosted-board subscription
  /// on [node] (the node is the board's Forum Host). Best-effort.
  Future<void> syncForNode(RemoteNode node) async {
    try {
      final subscriptions = (await _hostedBoardRepo.listSubscriptions(
        forumHostId: node.id,
      )).where((subscription) => subscription.readEnabled).toList();
      if (subscriptions.isEmpty) return;

      final projections = await _hostedBoardRepo.listProjections(
        forumHostId: node.id,
      );
      final projectionByHostedBoardId = {
        for (final projection in projections)
          projection.hostedBoardId: projection,
      };

      final client = _clientFactory(node.url);
      try {
        for (final subscription in subscriptions) {
          // hosted_board_id → local board id via the projection.
          final projection =
              projectionByHostedBoardId[subscription.hostedBoardId];
          if (projection == null) continue;
          try {
            final state = await client.fetchBoardModerationState(
              subscription.hostedBoardId,
            );
            await _applyBoardState(projection.localBoardId, state);
          } catch (_) {
            // One board's fetch/apply failure never breaks the others —
            // the previous snapshot simply stays in place.
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Moderation overlay is best-effort; never break the sync pass.
    }
  }

  Future<void> _applyBoardState(
    String localBoardId,
    BoardModerationState state,
  ) async {
    final updatedAt = _now();
    final entries = <HostModerationState>[
      for (final removed in state.removedPosts)
        HostModerationState(
          localBoardId: localBoardId,
          targetKind: HostModerationState.targetKindPost,
          targetRef: removed.targetRef,
          action: HostModerationState.actionRemoved,
          reasonCode: removed.reasonCode,
          updatedAt: updatedAt,
        ),
      for (final locked in state.lockedThreads)
        HostModerationState(
          localBoardId: localBoardId,
          targetKind: HostModerationState.targetKindThread,
          targetRef: locked.targetRef,
          action: HostModerationState.actionLocked,
          reasonCode: locked.reasonCode,
          updatedAt: updatedAt,
        ),
    ];

    final fresh = await _moderationRepo.replaceForBoard(localBoardId, entries);
    for (final entry in fresh) {
      await _notifyIfOwnContent(entry);
    }
  }

  /// Emits a `moderation_outcome` notification when a NEW entry targets
  /// content the local user authored.
  Future<void> _notifyIfOwnContent(HostModerationState entry) async {
    final projector = _notificationProjector;
    final localDid = _localDid;
    if (projector == null || localDid == null || localDid.isEmpty) return;

    String? authorId;
    String? threadId;
    if (entry.targetKind == HostModerationState.targetKindPost) {
      final post = await _postRepo?.getById(entry.targetRef);
      authorId = post?.authorId;
      threadId = post?.threadId;
    } else {
      final thread = await _threadRepo?.getById(entry.targetRef);
      authorId = thread?.authorId;
      threadId = thread?.id;
    }
    if (authorId != localDid) return;

    await projector.onModerationOutcome(
      targetKind: entry.targetKind,
      targetRef: entry.targetRef,
      boardId: entry.localBoardId,
      threadId: threadId,
      reasonCode: entry.reasonCode,
      action: entry.action,
      occurredAt: entry.updatedAt,
    );
  }
}
