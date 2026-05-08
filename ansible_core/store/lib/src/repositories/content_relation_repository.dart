import '../entities/content_relation.dart';

abstract class ContentRelationRepository {
  Future<void> create(ContentRelation relation);
  Future<List<ContentRelation>> sourcesFor(String contentItemId);
  Future<List<ContentRelation>> derivedFrom(String contentItemId);
}
