/// A relay-scoped removal marker. It records that one remote distribution
/// source no longer serves an entity; it never authorizes deletion of the
/// device's canonical local row.
class RemoteTombstone {
  final String sourceNodeId;
  final String entityType;
  final String entityId;
  final String? boardId;
  final String? authorDid;
  final String deletedByDid;
  final DateTime deletedAt;
  final DateTime receivedAt;

  const RemoteTombstone({
    required this.sourceNodeId,
    required this.entityType,
    required this.entityId,
    this.boardId,
    this.authorDid,
    required this.deletedByDid,
    required this.deletedAt,
    required this.receivedAt,
  });
}
