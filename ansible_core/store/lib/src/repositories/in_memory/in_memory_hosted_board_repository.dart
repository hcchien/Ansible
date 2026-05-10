import '../../entities/board_publication_target.dart';
import '../../entities/board_subscription.dart';
import '../../entities/hosted_board_projection.dart';
import '../hosted_board_repository.dart';

class InMemoryHostedBoardRepository implements HostedBoardRepository {
  final Map<String, HostedBoardProjection> _projectionsByLocalId = {};
  final Map<String, BoardSubscription> _subscriptions = {};
  final Map<String, BoardPublicationTarget> _targets = {};

  @override
  Future<HostedBoardProjection?> getProjection(
    String forumHostId,
    String hostedBoardId,
  ) async {
    for (final projection in _projectionsByLocalId.values) {
      if (projection.forumHostId == forumHostId &&
          projection.hostedBoardId == hostedBoardId) {
        return projection;
      }
    }
    return null;
  }

  @override
  Future<HostedBoardProjection?> getProjectionByLocalBoardId(
    String localBoardId,
  ) async {
    return _projectionsByLocalId[localBoardId];
  }

  @override
  Future<List<HostedBoardProjection>> listProjections({
    String? forumHostId,
  }) async {
    final projections = _projectionsByLocalId.values.where((projection) {
      return forumHostId == null || projection.forumHostId == forumHostId;
    }).toList()..sort((a, b) => a.localSlug.compareTo(b.localSlug));
    return projections;
  }

  @override
  Future<void> upsertProjection(HostedBoardProjection projection) async {
    for (final current in _projectionsByLocalId.values) {
      if (current.localSlug == projection.localSlug &&
          current.localBoardId != projection.localBoardId) {
        throw StateError(
          'Hosted board localSlug "${projection.localSlug}" already belongs to ${current.localBoardId}',
        );
      }
    }
    _projectionsByLocalId[projection.localBoardId] = projection;
  }

  @override
  Future<List<BoardSubscription>> listSubscriptions({
    String? forumHostId,
  }) async {
    final subscriptions = _subscriptions.values.where((subscription) {
      return forumHostId == null || subscription.forumHostId == forumHostId;
    }).toList()..sort((a, b) => a.subscriptionId.compareTo(b.subscriptionId));
    return subscriptions;
  }

  @override
  Future<void> updateSubscriptionCursor(
    String subscriptionId,
    int cursor,
    DateTime updatedAt,
  ) async {
    final subscription = _subscriptions[subscriptionId];
    if (subscription == null) return;
    _subscriptions[subscriptionId] = subscription.copyWith(
      syncCursor: cursor,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> upsertSubscription(BoardSubscription subscription) async {
    _subscriptions[subscription.subscriptionId] = subscription;
  }

  @override
  Future<List<BoardPublicationTarget>> listPublicationTargets({
    BoardPublicationStatus? status,
    String? forumHostId,
  }) async {
    final targets = _targets.values.where((target) {
      if (status != null && target.status != status) return false;
      if (forumHostId != null && target.forumHostId != forumHostId) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.targetId.compareTo(b.targetId));
    return targets;
  }

  @override
  Future<void> upsertPublicationTarget(BoardPublicationTarget target) async {
    _targets[target.targetId] = target;
  }
}
