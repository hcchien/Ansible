import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';

typedef SummaryNoteIdFactory = String Function();
typedef SummaryClock = DateTime Function();

class SummaryAssistanceService {
  final ContentItemRepository _contentItems;
  final SummaryJobRepository _summaryJobs;
  final SummaryNoteIdFactory _idFactory;
  final SummaryClock _clock;

  const SummaryAssistanceService({
    required ContentItemRepository contentItemRepository,
    required SummaryJobRepository summaryJobRepository,
    required SummaryNoteIdFactory idFactory,
    SummaryClock? clock,
  }) : _contentItems = contentItemRepository,
       _summaryJobs = summaryJobRepository,
       _idFactory = idFactory,
       _clock = clock ?? DateTime.now;

  Future<ContentItem> saveSummaryAsPrivateNote({
    required String summaryJobId,
    required String authorDid,
    required String title,
  }) async {
    final job = await _summaryJobs.getById(summaryJobId);
    if (job == null) {
      throw ArgumentError('Summary job "$summaryJobId" was not found');
    }
    if (job.status != SummaryJobStatus.completed) {
      throw ArgumentError('Summary job must be completed before saving');
    }
    final resultJson = job.resultJson;
    if (resultJson == null || resultJson.isEmpty) {
      throw ArgumentError('Summary job has no result');
    }
    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    final now = _clock().toUtc();
    final note = ContentItem(
      id: _idFactory(),
      authorDid: authorDid,
      mode: ContentMode.note,
      title: title,
      body: result['summary']?.toString() ?? resultJson,
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
    );
    await _contentItems.create(note);
    return note;
  }
}
