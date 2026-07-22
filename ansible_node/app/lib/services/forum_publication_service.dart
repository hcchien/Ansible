import 'package:ansible_store/ansible_store.dart';

class ForumPublicationResult {
  final int accepted;
  final int rejected;
  final List<String> errors;

  /// Target ids (subscription ids) that were skipped because the
  /// subscription is missing or not write-enabled. Callers surface these as
  /// a non-blocking "could not cross-post" notice — the primary publication
  /// is never blocked by a failed cross-post target.
  final List<String> rejectedTargetIds;

  const ForumPublicationResult({
    required this.accepted,
    this.rejected = 0,
    this.errors = const [],
    this.rejectedTargetIds = const [],
  });
}

class ForumPublicationService {
  final HostedBoardRepository hostedBoards;
  final ContentItemRepository? contentItems;
  final DateTime Function() now;

  ForumPublicationService({
    required this.hostedBoards,
    this.contentItems,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<ForumPublicationResult> createThread({
    required String localDraftId,
    required String primaryTargetId,
    List<String> crossPostTargetIds = const [],
  }) async {
    if (primaryTargetId.trim().isEmpty) {
      return const ForumPublicationResult(
        accepted: 0,
        rejected: 1,
        errors: ['primary_target_required'],
      );
    }

    final outcome = await _createTargets(
      localSourceId: localDraftId,
      sourceType: BoardPublicationSourceType.threadDraft,
      targetModes: {
        primaryTargetId: BoardPublicationMode.primary,
        for (final targetId in crossPostTargetIds)
          if (targetId != primaryTargetId)
            targetId: BoardPublicationMode.crossPost,
      },
    );
    return ForumPublicationResult(
      accepted: outcome.accepted,
      rejected: outcome.rejectedTargetIds.length,
      rejectedTargetIds: outcome.rejectedTargetIds,
    );
  }

  /// Composer-facing variant of [createThread]: resolves the primary local
  /// board's hosted-board subscription itself (composers know local board
  /// ids, not subscription ids). Returns null when the primary board is
  /// local-only and no cross-post targets were selected — nothing leaves the
  /// device unless the user chose a distribution path (Base Rule 2).
  Future<ForumPublicationResult?> createThreadForLocalBoard({
    required String localDraftId,
    required String primaryLocalBoardId,
    List<String> crossPostTargetIds = const [],
  }) async {
    final subscriptions = await hostedBoards.listSubscriptions();
    BoardSubscription? primary;
    for (final subscription in subscriptions) {
      if (subscription.localBoardId == primaryLocalBoardId &&
          subscription.writeEnabled) {
        primary = subscription;
        break;
      }
    }
    if (primary == null && crossPostTargetIds.isEmpty) return null;

    final outcome = await _createTargets(
      localSourceId: localDraftId,
      sourceType: BoardPublicationSourceType.threadDraft,
      targetModes: {
        if (primary != null)
          primary.subscriptionId: BoardPublicationMode.primary,
        for (final targetId in crossPostTargetIds)
          if (targetId != primary?.subscriptionId)
            targetId: BoardPublicationMode.crossPost,
      },
    );
    return ForumPublicationResult(
      accepted: outcome.accepted,
      rejected: outcome.rejectedTargetIds.length,
      rejectedTargetIds: outcome.rejectedTargetIds,
    );
  }

  /// Human-readable local board titles for [targetIds] (subscription ids),
  /// for user-facing publication notices. Falls back to the raw id when the
  /// subscription or local board row is gone.
  Future<List<String>> boardTitlesForTargets(
    BoardRepository boards,
    List<String> targetIds,
  ) async {
    if (targetIds.isEmpty) return const [];
    final subscriptions = await hostedBoards.listSubscriptions();
    final subscriptionById = {
      for (final subscription in subscriptions)
        subscription.subscriptionId: subscription,
    };
    final titles = <String>[];
    for (final targetId in targetIds) {
      final subscription = subscriptionById[targetId];
      final board = subscription == null
          ? null
          : await boards.getById(subscription.localBoardId);
      titles.add(board?.title ?? targetId);
    }
    return titles;
  }

  Future<ForumPublicationResult> projectContentItem({
    required String contentItemId,
    required List<String> targetIds,
  }) async {
    final repository = contentItems;
    if (repository == null) {
      return const ForumPublicationResult(
        accepted: 0,
        rejected: 1,
        errors: ['content_repository_required'],
      );
    }
    final item = await repository.getById(contentItemId);
    if (item == null) {
      return const ForumPublicationResult(
        accepted: 0,
        rejected: 1,
        errors: ['content_item_not_found'],
      );
    }
    if (item.visibility == ContentVisibility.private || item.localOnly) {
      return const ForumPublicationResult(
        accepted: 0,
        rejected: 1,
        errors: ['private_content_not_projectable'],
      );
    }

    final outcome = await _createTargets(
      localSourceId: contentItemId,
      sourceType: BoardPublicationSourceType.contentItem,
      targetModes: {
        for (final targetId in targetIds)
          targetId: BoardPublicationMode.projection,
      },
    );
    return ForumPublicationResult(
      accepted: outcome.accepted,
      rejected: outcome.rejectedTargetIds.length,
      rejectedTargetIds: outcome.rejectedTargetIds,
    );
  }

  Future<({int accepted, List<String> rejectedTargetIds})> _createTargets({
    required String localSourceId,
    required BoardPublicationSourceType sourceType,
    required Map<String, BoardPublicationMode> targetModes,
  }) async {
    final subscriptions = await hostedBoards.listSubscriptions();
    final subscriptionById = {
      for (final subscription in subscriptions)
        subscription.subscriptionId: subscription,
    };
    var accepted = 0;
    final rejectedTargetIds = <String>[];
    final timestamp = now().toUtc();
    for (final entry in targetModes.entries) {
      final subscription = subscriptionById[entry.key];
      if (subscription == null || !subscription.writeEnabled) {
        rejectedTargetIds.add(entry.key);
        continue;
      }
      await hostedBoards.upsertPublicationTarget(
        BoardPublicationTarget(
          targetId: _targetId(
            localSourceId,
            subscription.subscriptionId,
            entry.value,
          ),
          localSourceId: localSourceId,
          sourceType: sourceType,
          forumHostId: subscription.forumHostId,
          hostedBoardId: subscription.hostedBoardId,
          mode: entry.value,
          status: BoardPublicationStatus.pending,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      accepted += 1;
    }
    return (accepted: accepted, rejectedTargetIds: rejectedTargetIds);
  }

  String _targetId(
    String localSourceId,
    String subscriptionId,
    BoardPublicationMode mode,
  ) {
    return '${localSourceId}_${subscriptionId}_${mode.name}';
  }
}
