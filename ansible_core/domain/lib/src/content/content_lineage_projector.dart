import 'package:ansible_store/ansible_store.dart';

class ContentLineageEdge {
  final ContentRelation relation;
  final ContentItem contentItem;

  const ContentLineageEdge({required this.relation, required this.contentItem});
}

class ContentLineageProjector {
  final ContentItemRepository _contentItems;
  final ContentRelationRepository _contentRelations;

  const ContentLineageProjector({
    required ContentItemRepository contentItemRepository,
    required ContentRelationRepository contentRelationRepository,
  }) : _contentItems = contentItemRepository,
       _contentRelations = contentRelationRepository;

  Future<List<ContentLineageEdge>> sourcesFor(String contentItemId) async {
    final relations = await _contentRelations.sourcesFor(contentItemId);
    return _resolveEdges(
      relations,
      targetIdFor: (relation) => relation.toContentItemId,
    );
  }

  Future<List<ContentLineageEdge>> derivedFrom(String contentItemId) async {
    final relations = await _contentRelations.derivedFrom(contentItemId);
    return _resolveEdges(
      relations,
      targetIdFor: (relation) => relation.fromContentItemId,
    );
  }

  Future<List<ContentLineageEdge>> _resolveEdges(
    List<ContentRelation> relations, {
    required String Function(ContentRelation relation) targetIdFor,
  }) async {
    final edges = <ContentLineageEdge>[];
    for (final relation in relations) {
      final contentItem = await _contentItems.getById(targetIdFor(relation));
      if (contentItem == null) continue;
      edges.add(
        ContentLineageEdge(relation: relation, contentItem: contentItem),
      );
    }
    return edges;
  }
}
