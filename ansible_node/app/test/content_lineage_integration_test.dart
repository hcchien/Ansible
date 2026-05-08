import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates Murmur -> Note -> Discussion and inspects lineage', () async {
    final contentItems = InMemoryContentItemRepository();
    final contentRelations = InMemoryContentRelationRepository();
    final transformationJobs = InMemoryTransformationJobRepository();
    final projections = InMemoryProjectionRepository();
    final threads = InMemoryThreadRepository();
    final lineage = ContentLineageProjector(
      contentItemRepository: contentItems,
      contentRelationRepository: contentRelations,
    );
    final service = ContentTransformationService(
      contentItemRepository: contentItems,
      contentRelationRepository: contentRelations,
      transformationJobRepository: transformationJobs,
      projectionRepository: projections,
      threadRepository: threads,
      idFactory: _SequenceIds(),
      clock: () => DateTime.utc(2026, 5, 8, 12),
    );

    final murmur = ContentItem(
      id: 'murmur-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.murmur,
      body: 'Raw thought about public decision making.',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 8, 11),
      updatedAt: DateTime.utc(2026, 5, 8, 11),
    );
    await contentItems.create(murmur);

    final note = await service.acceptManualMurmurToNote(
      authorDid: 'did:plc:alice',
      sourceMurmurs: [murmur],
      noteTitle: 'Decision note',
      noteBody: 'Structured note from the murmur.',
    );
    final discussion = await service.acceptNoteToDiscussion(
      authorDid: 'did:plc:alice',
      sourceNote: note,
      title: 'How should public decisions be reviewed?',
      body: 'A public discussion created from a private note.',
      ownershipTransferAcknowledged: true,
    );

    expect(note.mode, ContentMode.note);
    expect(note.visibility, ContentVisibility.private);
    expect(discussion.mode, ContentMode.discussion);
    expect(discussion.visibility, ContentVisibility.public);
    expect(discussion.localOnly, isFalse);

    final noteSources = await lineage.sourcesFor(note.id);
    expect(noteSources.single.contentItem.id, murmur.id);
    expect(noteSources.single.relation.relationType, RelationType.expandedFrom);

    final discussionSources = await lineage.sourcesFor(discussion.id);
    expect(discussionSources.single.contentItem.id, note.id);
    expect(
      discussionSources.single.relation.relationType,
      RelationType.projectedFrom,
    );

    final projection = await projections.getById('projection-1');
    expect(projection, isNotNull);
    expect(projection!.ownershipTransferAcknowledged, isTrue);
  });
}

class _SequenceIds implements ContentTransformationIdFactory {
  var _nextContent = 0;
  var _nextTransformation = 0;
  var _nextRelation = 0;
  var _nextProjection = 0;
  var _nextThread = 0;

  @override
  String nextContentItemId() {
    _nextContent += 1;
    return 'content-$_nextContent';
  }

  @override
  String nextTransformationJobId() {
    _nextTransformation += 1;
    return 'transformation-$_nextTransformation';
  }

  @override
  String nextContentRelationId() {
    _nextRelation += 1;
    return 'relation-$_nextRelation';
  }

  @override
  String nextProjectionId() {
    _nextProjection += 1;
    return 'projection-$_nextProjection';
  }

  @override
  String nextThreadId() {
    _nextThread += 1;
    return 'thread-$_nextThread';
  }
}
