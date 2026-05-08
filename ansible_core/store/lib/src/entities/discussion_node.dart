class DiscussionNode {
  final String id;
  final String discussionId;
  final String authorDid;
  final String nodeType;
  final String stance;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? parentNodeId;
  final bool isDeleted;

  const DiscussionNode({
    required this.id,
    required this.discussionId,
    required this.authorDid,
    required this.nodeType,
    required this.stance,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.parentNodeId,
    this.isDeleted = false,
  });
}
