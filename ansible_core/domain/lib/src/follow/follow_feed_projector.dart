import 'package:ansible_store/ansible_store.dart';

enum FollowFeedReason { followedUser, followedBoard }

class FollowFeedEntry {
  final Post post;
  final Thread thread;
  final Board? board;
  final Set<FollowFeedReason> reasons;

  const FollowFeedEntry({
    required this.post,
    required this.thread,
    required this.board,
    required this.reasons,
  });
}

class FollowFeedProjector {
  final FollowRepository followRepository;
  final BoardRepository boardRepository;
  final ThreadRepository threadRepository;
  final PostRepository postRepository;

  FollowFeedProjector({
    required this.followRepository,
    required this.boardRepository,
    required this.threadRepository,
    required this.postRepository,
  });

  Future<List<FollowFeedEntry>> project({required String followerDid}) async {
    final followedUsers = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.user,
    );
    final followedBoards = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.board,
    );

    final followedUserDids = await _resolveFollowedUserDids(followedUsers);
    final followedBoardIds = await _resolveFollowedBoardIds(followedBoards);

    final boards = await boardRepository.list();
    final boardById = {for (final board in boards) board.id: board};
    final threads = await threadRepository.list();
    final entriesByPostId = <String, FollowFeedEntry>{};

    for (final thread in threads) {
      final posts = await postRepository.list(threadId: thread.id);
      for (final post in posts.where((post) => !post.isDeleted)) {
        final reasons = <FollowFeedReason>{};
        if (followedUserDids.contains(post.authorId)) {
          reasons.add(FollowFeedReason.followedUser);
        }
        if (followedBoardIds.contains(post.boardId)) {
          reasons.add(FollowFeedReason.followedBoard);
        }
        if (reasons.isEmpty) continue;

        entriesByPostId[post.id] = FollowFeedEntry(
          post: post,
          thread: thread,
          board: boardById[post.boardId],
          reasons: Set.unmodifiable(reasons),
        );
      }
    }

    return entriesByPostId.values.toList()..sort((a, b) {
      final byEdit = b.post.lastEditAt.compareTo(a.post.lastEditAt);
      if (byEdit != 0) return byEdit;
      return b.post.createdAt.compareTo(a.post.createdAt);
    });
  }

  Future<Set<String>> _resolveFollowedUserDids(List<FollowEdge> edges) async {
    final dids = <String>{};
    for (final edge in edges.where(
      (edge) => edge.status == FollowStatus.accepted,
    )) {
      final target = await followRepository.getTarget(edge.targetId);
      final did = target?.did ?? target?.canonicalUri;
      if (did != null && did.isNotEmpty) {
        dids.add(did);
      }
    }
    return dids;
  }

  Future<Set<String>> _resolveFollowedBoardIds(List<FollowEdge> edges) async {
    final boardIds = <String>{};
    for (final edge in edges.where(
      (edge) => edge.status == FollowStatus.accepted,
    )) {
      final target = await followRepository.getTarget(edge.targetId);
      final boardId = target?.boardId;
      if (boardId != null && boardId.isNotEmpty) {
        boardIds.add(boardId);
      }
    }
    return boardIds;
  }
}
