import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('ContentTransformationService', () {
    late InMemoryContentItemRepository contentItems;
    late InMemoryContentRelationRepository contentRelations;
    late InMemoryTransformationJobRepository transformationJobs;
    late InMemoryProjectionRepository projections;
    late InMemoryThreadRepository threads;
    late ContentLineageProjector lineageProjector;
    late ContentTransformationService service;

    setUp(() {
      contentItems = InMemoryContentItemRepository();
      contentRelations = InMemoryContentRelationRepository();
      transformationJobs = InMemoryTransformationJobRepository();
      projections = InMemoryProjectionRepository();
      threads = InMemoryThreadRepository();
      lineageProjector = ContentLineageProjector(
        contentItemRepository: contentItems,
        contentRelationRepository: contentRelations,
      );
      service = ContentTransformationService(
        contentItemRepository: contentItems,
        contentRelationRepository: contentRelations,
        transformationJobRepository: transformationJobs,
        projectionRepository: projections,
        threadRepository: threads,
        idFactory: _SequenceIds(),
        clock: () => DateTime.utc(2026, 5, 8, 12),
      );
    });

    test('accepts manual Murmur to Note transformation', () async {
      final murmurs = [
        _murmur('murmur-1', 'First raw thought'),
        _murmur('murmur-2', 'Second raw thought'),
      ];
      for (final murmur in murmurs) {
        await contentItems.create(murmur);
      }

      final note = await service.acceptManualMurmurToNote(
        authorDid: 'did:plc:alice',
        sourceMurmurs: murmurs,
        noteTitle: 'Structured note',
        noteBody: 'A clearer version of the thought.',
      );

      expect(note.id, 'content-1');
      expect(note.mode, ContentMode.note);
      expect(note.title, 'Structured note');
      expect(note.body, 'A clearer version of the thought.');
      expect(note.visibility, ContentVisibility.private);
      expect(note.localOnly, isTrue);
      expect(await contentItems.getById(note.id), isNotNull);

      final job = await transformationJobs.getById('transformation-1');
      expect(job, isNotNull);
      expect(job!.targetMode, ContentMode.note);
      expect(job.providerType, AiProviderType.manual);
      expect(job.status, TransformationJobStatus.accepted);
      expect(job.outputSnapshotJson, contains(note.id));

      final jobSources = await transformationJobs.listSources(job.id);
      expect(jobSources.map((source) => source.contentItemId), [
        'murmur-1',
        'murmur-2',
      ]);

      final sources = await contentRelations.sourcesFor(note.id);
      expect(sources.map((relation) => relation.toContentItemId), [
        'murmur-1',
        'murmur-2',
      ]);
      expect(sources.map((relation) => relation.relationType).toSet(), {
        RelationType.expandedFrom,
      });
    });

    test(
      'accepts Note to Discussion projection after acknowledgement',
      () async {
        final sourceNote = ContentItem(
          id: 'note-1',
          authorDid: 'did:plc:alice',
          mode: ContentMode.note,
          title: 'Private note',
          body: 'Private note body',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          createdAt: DateTime.utc(2026, 5, 8, 11),
          updatedAt: DateTime.utc(2026, 5, 8, 11),
        );
        await contentItems.create(sourceNote);

        expect(
          () => service.acceptNoteToDiscussion(
            authorDid: 'did:plc:alice',
            sourceNote: sourceNote,
            title: 'Public question',
            body: 'Public discussion body',
            ownershipTransferAcknowledged: false,
          ),
          throwsArgumentError,
        );

        final discussion = await service.acceptNoteToDiscussion(
          authorDid: 'did:plc:alice',
          sourceNote: sourceNote,
          title: 'Public question',
          body: 'Public discussion body',
          ownershipTransferAcknowledged: true,
        );

        expect(discussion.id, 'content-1');
        expect(discussion.mode, ContentMode.discussion);
        expect(discussion.title, 'Public question');
        expect(discussion.visibility, ContentVisibility.public);
        expect(discussion.localOnly, isFalse);

        final projection = await projections.getById('projection-1');
        expect(projection, isNotNull);
        expect(projection!.sourceContentItemId, 'note-1');
        expect(projection.targetDiscussionId, discussion.id);
        expect(projection.ownershipTransferAcknowledged, isTrue);

        final sources = await contentRelations.sourcesFor(discussion.id);
        expect(sources.single.toContentItemId, 'note-1');
        expect(sources.single.relationType, RelationType.projectedFrom);

        final thread = await threads.getById('thread-1');
        expect(thread, isNotNull);
        expect(thread!.title, 'Public question');
        expect(thread.authorId, 'did:plc:alice');
      },
    );

    test('projects lineage relations with source content items', () async {
      final murmur = _murmur('murmur-1', 'First raw thought');
      final note = ContentItem(
        id: 'note-1',
        authorDid: 'did:plc:alice',
        mode: ContentMode.note,
        body: 'Expanded thought',
        status: ContentStatus.active,
        visibility: ContentVisibility.private,
        createdAt: DateTime.utc(2026, 5, 8, 12),
        updatedAt: DateTime.utc(2026, 5, 8, 12),
      );
      await contentItems.create(murmur);
      await contentItems.create(note);
      await contentRelations.create(
        ContentRelation(
          id: 'relation-1',
          fromContentItemId: note.id,
          toContentItemId: murmur.id,
          relationType: RelationType.expandedFrom,
          createdByDid: 'did:plc:alice',
          createdAt: DateTime.utc(2026, 5, 8, 12),
        ),
      );

      final sources = await lineageProjector.sourcesFor(note.id);
      final derived = await lineageProjector.derivedFrom(murmur.id);

      expect(sources.single.contentItem.id, 'murmur-1');
      expect(sources.single.relation.relationType, RelationType.expandedFrom);
      expect(derived.single.contentItem.id, 'note-1');
    });
  });
}

ContentItem _murmur(String id, String body) {
  final now = DateTime.utc(2026, 5, 8, 11);
  return ContentItem(
    id: id,
    authorDid: 'did:plc:alice',
    mode: ContentMode.murmur,
    body: body,
    status: ContentStatus.draft,
    visibility: ContentVisibility.private,
    createdAt: now,
    updatedAt: now,
  );
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
