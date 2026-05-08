import '../../entities/discussion_node.dart';
import '../discussion_node_repository.dart';

class InMemoryDiscussionNodeRepository implements DiscussionNodeRepository {
  final Map<String, DiscussionNode> _nodes = {};

  @override
  Future<void> create(DiscussionNode node) async {
    _nodes[node.id] = node;
  }

  @override
  Future<List<DiscussionNode>> listByDiscussion(String discussionId) async {
    return _nodes.values
        .where((node) => node.discussionId == discussionId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}
