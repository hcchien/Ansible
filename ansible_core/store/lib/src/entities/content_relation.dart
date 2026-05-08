enum RelationType {
  expandedFrom,
  projectedFrom,
  summarizedFrom,
  forkedFrom,
  supports,
  rebuts,
  references;

  static RelationType parse(String value) {
    return RelationType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown RelationType "$value"'),
    );
  }
}

class ContentRelation {
  final String id;
  final String fromContentItemId;
  final String toContentItemId;
  final RelationType relationType;
  final String createdByDid;
  final DateTime createdAt;
  final bool localOnly;

  const ContentRelation({
    required this.id,
    required this.fromContentItemId,
    required this.toContentItemId,
    required this.relationType,
    required this.createdByDid,
    required this.createdAt,
    this.localOnly = true,
  });
}
