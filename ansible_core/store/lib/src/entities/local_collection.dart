class LocalCollection {
  final String collectionId;
  final String ownerDid;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const LocalCollection({
    required this.collectionId,
    required this.ownerDid,
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  LocalCollection copyWith({
    String? collectionId,
    String? ownerDid,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return LocalCollection(
      collectionId: collectionId ?? this.collectionId,
      ownerDid: ownerDid ?? this.ownerDid,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
