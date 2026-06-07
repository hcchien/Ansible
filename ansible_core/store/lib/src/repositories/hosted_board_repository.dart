import '../entities/board_publication_target.dart';
import '../entities/board_subscription.dart';
import '../entities/hosted_board_projection.dart';

abstract class HostedBoardRepository {
  Future<void> upsertProjection(HostedBoardProjection projection);
  Future<HostedBoardProjection?> getProjection(
    String forumHostId,
    String hostedBoardId,
  );
  Future<HostedBoardProjection?> getProjectionByLocalBoardId(
    String localBoardId,
  );
  Future<List<HostedBoardProjection>> listProjections({String? forumHostId});

  Future<void> upsertSubscription(BoardSubscription subscription);
  Future<List<BoardSubscription>> listSubscriptions({String? forumHostId});

  /// Unsubscribes a board: removes its projection and subscription for the given
  /// local board id (the device stops syncing it).
  Future<void> removeForLocalBoard(String localBoardId);
  Future<void> updateSubscriptionCursor(
    String subscriptionId,
    int cursor,
    DateTime updatedAt,
  );

  Future<void> upsertPublicationTarget(BoardPublicationTarget target);
  Future<List<BoardPublicationTarget>> listPublicationTargets({
    BoardPublicationStatus? status,
    String? forumHostId,
  });
}
