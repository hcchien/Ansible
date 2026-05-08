import '../entities/discussion_node.dart';

abstract class DiscussionNodeRepository {
  Future<void> create(DiscussionNode node);
  Future<List<DiscussionNode>> listByDiscussion(String discussionId);
}
