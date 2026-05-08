class Projection {
  final String id;
  final String sourceContentItemId;
  final String targetDiscussionId;
  final String projectedExcerpt;
  final String participationPolicy;
  final bool ownershipTransferAcknowledged;
  final String createdByDid;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;

  const Projection({
    required this.id,
    required this.sourceContentItemId,
    required this.targetDiscussionId,
    required this.projectedExcerpt,
    required this.participationPolicy,
    required this.ownershipTransferAcknowledged,
    required this.createdByDid,
    required this.createdAt,
    this.acknowledgedAt,
  });
}
