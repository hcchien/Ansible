import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';

typedef ContentTransformationClock = DateTime Function();

abstract class ContentTransformationIdFactory {
  String nextContentItemId();
  String nextTransformationJobId();
  String nextContentRelationId();
  String nextProjectionId();
  String nextThreadId();
}

class ContentTransformationService {
  final ContentItemRepository _contentItems;
  final ContentRelationRepository _contentRelations;
  final TransformationJobRepository _transformationJobs;
  final ProjectionRepository _projections;
  final ThreadRepository _threads;
  final ContentTransformationIdFactory _idFactory;
  final ContentTransformationClock _clock;
  final String _compatibilityBoardId;

  ContentTransformationService({
    required ContentItemRepository contentItemRepository,
    required ContentRelationRepository contentRelationRepository,
    required TransformationJobRepository transformationJobRepository,
    required ProjectionRepository projectionRepository,
    required ThreadRepository threadRepository,
    required ContentTransformationIdFactory idFactory,
    ContentTransformationClock? clock,
    String compatibilityBoardId = 'content-lineage',
  }) : _contentItems = contentItemRepository,
       _contentRelations = contentRelationRepository,
       _transformationJobs = transformationJobRepository,
       _projections = projectionRepository,
       _threads = threadRepository,
       _idFactory = idFactory,
       _clock = clock ?? DateTime.now,
       _compatibilityBoardId = compatibilityBoardId;

  Future<ContentItem> acceptManualMurmurToNote({
    required String authorDid,
    required List<ContentItem> sourceMurmurs,
    required String noteBody,
    String? noteTitle,
  }) async {
    if (sourceMurmurs.isEmpty) {
      throw ArgumentError('At least one source murmur is required');
    }
    for (final murmur in sourceMurmurs) {
      if (murmur.mode != ContentMode.murmur) {
        throw ArgumentError('Source content must be murmurs');
      }
    }

    final now = _clock().toUtc();
    final note = ContentItem(
      id: _idFactory.nextContentItemId(),
      authorDid: authorDid,
      mode: ContentMode.note,
      title: noteTitle,
      body: noteBody,
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
    );
    final job = TransformationJob(
      id: _idFactory.nextTransformationJobId(),
      requestedByDid: authorDid,
      targetMode: ContentMode.note,
      providerType: AiProviderType.manual,
      status: TransformationJobStatus.drafting,
      inputSnapshotJson: jsonEncode({
        'sourceContentItemIds': sourceMurmurs.map((item) => item.id).toList(),
      }),
      createdAt: now,
      updatedAt: now,
    );

    await _transformationJobs.create(job);
    for (var index = 0; index < sourceMurmurs.length; index += 1) {
      await _transformationJobs.addSource(
        TransformationSource(
          transformationJobId: job.id,
          contentItemId: sourceMurmurs[index].id,
          sourceOrder: index,
        ),
      );
    }
    await _contentItems.create(note);
    for (final murmur in sourceMurmurs) {
      await _contentRelations.create(
        ContentRelation(
          id: _idFactory.nextContentRelationId(),
          fromContentItemId: note.id,
          toContentItemId: murmur.id,
          relationType: RelationType.expandedFrom,
          createdByDid: authorDid,
          createdAt: now,
        ),
      );
    }
    await _transformationJobs.markCompleted(
      job.id,
      outputSnapshotJson: jsonEncode({'contentItemId': note.id}),
      completedAt: now,
    );
    await _transformationJobs.markAccepted(job.id, acceptedAt: now);

    return note;
  }

  Future<ContentItem> acceptNoteToDiscussion({
    required String authorDid,
    required ContentItem sourceNote,
    required String title,
    required String body,
    required bool ownershipTransferAcknowledged,
  }) async {
    if (!ownershipTransferAcknowledged) {
      throw ArgumentError('Ownership transfer acknowledgement is required');
    }
    if (sourceNote.mode != ContentMode.note) {
      throw ArgumentError('Source content must be a note');
    }

    final now = _clock().toUtc();
    final discussion = ContentItem(
      id: _idFactory.nextContentItemId(),
      authorDid: authorDid,
      subjectId: sourceNote.subjectId,
      mode: ContentMode.discussion,
      title: title,
      body: body,
      status: ContentStatus.active,
      visibility: ContentVisibility.public,
      publishedAt: now,
      createdAt: now,
      updatedAt: now,
      localOnly: false,
    );
    final thread = Thread(
      id: _idFactory.nextThreadId(),
      boardId: sourceNote.subjectId ?? _compatibilityBoardId,
      title: title,
      authorId: authorDid,
      createdAt: now,
      updatedAt: now,
    );

    await _contentItems.create(discussion);
    await _threads.create(thread);
    await _projections.create(
      Projection(
        id: _idFactory.nextProjectionId(),
        sourceContentItemId: sourceNote.id,
        targetDiscussionId: discussion.id,
        projectedExcerpt: body,
        participationPolicy: 'public',
        ownershipTransferAcknowledged: true,
        acknowledgedAt: now,
        createdByDid: authorDid,
        createdAt: now,
      ),
    );
    await _contentRelations.create(
      ContentRelation(
        id: _idFactory.nextContentRelationId(),
        fromContentItemId: discussion.id,
        toContentItemId: sourceNote.id,
        relationType: RelationType.projectedFrom,
        createdByDid: authorDid,
        createdAt: now,
        localOnly: false,
      ),
    );

    return discussion;
  }
}
