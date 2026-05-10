import 'package:ansible_store/ansible_store.dart';

class ForumPublicationResult {
  final int accepted;
  final int rejected;
  final List<String> errors;

  const ForumPublicationResult({
    required this.accepted,
    this.rejected = 0,
    this.errors = const [],
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

    final accepted = await _createTargets(
      localSourceId: localDraftId,
      sourceType: BoardPublicationSourceType.threadDraft,
      targetModes: {
        primaryTargetId: BoardPublicationMode.primary,
        for (final targetId in crossPostTargetIds)
          targetId: BoardPublicationMode.crossPost,
      },
    );
    return ForumPublicationResult(accepted: accepted);
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

    final accepted = await _createTargets(
      localSourceId: contentItemId,
      sourceType: BoardPublicationSourceType.contentItem,
      targetModes: {
        for (final targetId in targetIds)
          targetId: BoardPublicationMode.projection,
      },
    );
    return ForumPublicationResult(accepted: accepted);
  }

  Future<int> _createTargets({
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
    final timestamp = now().toUtc();
    for (final entry in targetModes.entries) {
      final subscription = subscriptionById[entry.key];
      if (subscription == null || !subscription.writeEnabled) {
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
    return accepted;
  }

  String _targetId(
    String localSourceId,
    String subscriptionId,
    BoardPublicationMode mode,
  ) {
    return '${localSourceId}_${subscriptionId}_${mode.name}';
  }
}
