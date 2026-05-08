import '../../entities/content_relation.dart';
import '../content_relation_repository.dart';

class InMemoryContentRelationRepository implements ContentRelationRepository {
  final Map<String, ContentRelation> _relations = {};

  @override
  Future<void> create(ContentRelation relation) async {
    _relations[relation.id] = relation;
  }

  @override
  Future<List<ContentRelation>> derivedFrom(String contentItemId) async {
    return _relations.values
        .where((relation) => relation.toContentItemId == contentItemId)
        .toList()
      ..sort(_compareRelations);
  }

  @override
  Future<List<ContentRelation>> sourcesFor(String contentItemId) async {
    return _relations.values
        .where((relation) => relation.fromContentItemId == contentItemId)
        .toList()
      ..sort(_compareRelations);
  }

  int _compareRelations(ContentRelation a, ContentRelation b) {
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  }
}
