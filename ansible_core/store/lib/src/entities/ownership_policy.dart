class OwnershipPolicy {
  final String contentItemId;
  final String ownerDid;
  final String editPolicy;
  final String deletePolicy;
  final String commentPolicy;
  final String forkPolicy;
  final String moderationPolicy;
  final DateTime updatedAt;

  const OwnershipPolicy({
    required this.contentItemId,
    required this.ownerDid,
    required this.editPolicy,
    required this.deletePolicy,
    required this.commentPolicy,
    required this.forkPolicy,
    required this.moderationPolicy,
    required this.updatedAt,
  });
}
