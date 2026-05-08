import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('content lineage repositories', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('drift creates and lists content items by mode and author', () async {
      await _exercisesContentItems(DriftContentItemRepository(db));
    });

    test(
      'in-memory creates and lists content items by mode and author',
      () async {
        await _exercisesContentItems(InMemoryContentItemRepository());
      },
    );

    test('drift stores lineage relations in both directions', () async {
      await _exercisesContentRelations(
        DriftContentItemRepository(db),
        DriftContentRelationRepository(db),
      );
    });

    test('in-memory stores lineage relations in both directions', () async {
      await _exercisesContentRelations(
        InMemoryContentItemRepository(),
        InMemoryContentRelationRepository(),
      );
    });

    test('drift stores assistance jobs and review artifacts', () async {
      await _exercisesAssistanceRepositories(
        items: DriftContentItemRepository(db),
        transformationJobs: DriftTransformationJobRepository(db),
        providers: DriftAiProviderConfigRepository(db),
        contextPacks: DriftContextPackRepository(db),
        summaryJobs: DriftSummaryJobRepository(db),
        projections: DriftProjectionRepository(db),
      );
    });

    test('in-memory stores assistance jobs and review artifacts', () async {
      await _exercisesAssistanceRepositories(
        items: InMemoryContentItemRepository(),
        transformationJobs: InMemoryTransformationJobRepository(),
        providers: InMemoryAiProviderConfigRepository(),
        contextPacks: InMemoryContextPackRepository(),
        summaryJobs: InMemorySummaryJobRepository(),
        projections: InMemoryProjectionRepository(),
      );
    });
  });
}

Future<void> _exercisesContentItems(ContentItemRepository repository) async {
  final now = DateTime.utc(2026, 5, 8);
  final murmur = ContentItem(
    id: 'murmur-1',
    authorDid: 'did:plc:alice',
    mode: ContentMode.murmur,
    body: 'Raw thought',
    status: ContentStatus.draft,
    visibility: ContentVisibility.private,
    createdAt: now,
    updatedAt: now,
  );
  final note = ContentItem(
    id: 'note-1',
    authorDid: 'did:plc:alice',
    mode: ContentMode.note,
    title: 'Structured note',
    body: 'Expanded thought',
    status: ContentStatus.active,
    visibility: ContentVisibility.unlisted,
    createdAt: now,
    updatedAt: now,
    localOnly: false,
  );
  final otherAuthorPost = ContentItem(
    id: 'post-1',
    authorDid: 'did:plc:bob',
    mode: ContentMode.post,
    body: 'Reply',
    status: ContentStatus.active,
    visibility: ContentVisibility.public,
    createdAt: now,
    updatedAt: now,
    localOnly: false,
  );

  await repository.create(murmur);
  await repository.create(note);
  await repository.create(otherAuthorPost);

  final loadedMurmur = await repository.getById('murmur-1');
  expect(loadedMurmur!.mode, ContentMode.murmur);
  expect(loadedMurmur.visibility, ContentVisibility.private);
  expect(loadedMurmur.localOnly, isTrue);

  final notes = await repository.list(mode: ContentMode.note);
  expect(notes.map((item) => item.id), ['note-1']);

  final aliceItems = await repository.list(authorDid: 'did:plc:alice');
  expect(aliceItems.map((item) => item.id), ['murmur-1', 'note-1']);

  await repository.delete('note-1');
  expect((await repository.getById('note-1'))!.isDeleted, isTrue);
}

Future<void> _exercisesContentRelations(
  ContentItemRepository items,
  ContentRelationRepository relations,
) async {
  final now = DateTime.utc(2026, 5, 8);
  await items.create(
    ContentItem(
      id: 'murmur-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.murmur,
      body: 'Raw thought',
      status: ContentStatus.draft,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await items.create(
    ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      body: 'Expanded thought',
      status: ContentStatus.active,
      visibility: ContentVisibility.unlisted,
      createdAt: now,
      updatedAt: now,
    ),
  );

  await relations.create(
    ContentRelation(
      id: 'relation-1',
      fromContentItemId: 'note-1',
      toContentItemId: 'murmur-1',
      relationType: RelationType.expandedFrom,
      createdByDid: 'did:plc:alice',
      createdAt: now,
    ),
  );

  final sources = await relations.sourcesFor('note-1');
  expect(sources.single.toContentItemId, 'murmur-1');
  expect(sources.single.relationType, RelationType.expandedFrom);

  final derived = await relations.derivedFrom('murmur-1');
  expect(derived.single.fromContentItemId, 'note-1');
}

Future<void> _exercisesAssistanceRepositories({
  required ContentItemRepository items,
  required TransformationJobRepository transformationJobs,
  required AiProviderConfigRepository providers,
  required ContextPackRepository contextPacks,
  required SummaryJobRepository summaryJobs,
  required ProjectionRepository projections,
}) async {
  final now = DateTime.utc(2026, 5, 8);

  await items.create(
    ContentItem(
      id: 'murmur-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.murmur,
      body: 'Raw thought',
      status: ContentStatus.draft,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await items.create(
    ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      body: 'Expanded thought',
      status: ContentStatus.active,
      visibility: ContentVisibility.unlisted,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await items.create(
    ContentItem(
      id: 'discussion-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.discussion,
      body: 'Public discussion',
      status: ContentStatus.active,
      visibility: ContentVisibility.public,
      createdAt: now,
      updatedAt: now,
      localOnly: false,
    ),
  );

  await providers.save(
    AiProviderConfig(
      id: 'provider-1',
      displayName: 'Manual',
      providerType: AiProviderType.manual,
      modelName: 'human-review',
      apiKeyRef: 'keychain://provider-1',
      defaultForTransformations: true,
      createdAt: now,
      updatedAt: now,
    ),
  );
  final provider = await providers.getById('provider-1');
  expect(provider!.apiKeyRef, 'keychain://provider-1');
  expect(provider.defaultForTransformations, isTrue);

  await contextPacks.create(
    ContextPack(
      id: 'context-1',
      purpose: ContextPackPurpose.murmurToNote,
      sourceRefsJson: '["murmur-1"]',
      snapshotJson: '{"sources":["Raw thought"]}',
      privacyLevel: ContextPrivacyLevel.containsPrivate,
      allowedRemote: false,
      createdByDid: 'did:plc:alice',
      createdAt: now,
    ),
  );
  expect(
    (await contextPacks.getById('context-1'))!.privacyLevel,
    ContextPrivacyLevel.containsPrivate,
  );

  await transformationJobs.create(
    TransformationJob(
      id: 'job-1',
      requestedByDid: 'did:plc:alice',
      targetMode: ContentMode.note,
      providerType: AiProviderType.manual,
      status: TransformationJobStatus.drafting,
      inputSnapshotJson: '{"contextPackId":"context-1"}',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await transformationJobs.addSource(
    const TransformationSource(
      transformationJobId: 'job-1',
      contentItemId: 'murmur-1',
      sourceOrder: 0,
    ),
  );
  await transformationJobs.markCompleted(
    'job-1',
    outputSnapshotJson: '{"body":"Expanded thought"}',
    completedAt: now.add(const Duration(minutes: 1)),
  );
  await transformationJobs.markAccepted(
    'job-1',
    acceptedAt: now.add(const Duration(minutes: 2)),
  );

  final job = await transformationJobs.getById('job-1');
  expect(job!.status, TransformationJobStatus.accepted);
  expect(job.outputSnapshotJson, '{"body":"Expanded thought"}');
  expect(await transformationJobs.listSources('job-1'), hasLength(1));

  await projections.create(
    Projection(
      id: 'projection-1',
      sourceContentItemId: 'note-1',
      targetDiscussionId: 'discussion-1',
      projectedExcerpt: 'Expanded thought',
      participationPolicy: 'public',
      ownershipTransferAcknowledged: true,
      acknowledgedAt: now,
      createdByDid: 'did:plc:alice',
      createdAt: now,
    ),
  );
  expect(
    (await projections.getById('projection-1'))!.ownershipTransferAcknowledged,
    isTrue,
  );

  await summaryJobs.create(
    SummaryJob(
      id: 'summary-1',
      requestedByDid: 'did:plc:alice',
      contextPackId: 'context-1',
      providerConfigId: 'provider-1',
      summaryType: 'lineage',
      status: SummaryJobStatus.queued,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await summaryJobs.markCompleted(
    'summary-1',
    resultJson: '{"summary":"Short version"}',
    completedAt: now.add(const Duration(minutes: 3)),
  );
  expect(
    (await summaryJobs.getById('summary-1'))!.status,
    SummaryJobStatus.completed,
  );
}
