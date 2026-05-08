import 'dart:convert';

import 'package:ansible_node/services/ai/ai_provider.dart';
import 'package:ansible_node/services/ai/context_pack_builder.dart';
import 'package:ansible_node/services/ai/manual_ai_provider.dart';
import 'package:ansible_node/services/ai/summary_assistance_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'summarizes a discussion with manual provider and saves private note',
    () async {
      final contentItems = InMemoryContentItemRepository();
      final contextPacks = InMemoryContextPackRepository();
      final summaryJobs = InMemorySummaryJobRepository();
      final builder = ContextPackBuilder(
        idFactory: () => 'context-1',
        clock: () => DateTime.utc(2026, 5, 8, 12),
      );
      final provider = ManualAiProvider();
      final summaryService = SummaryAssistanceService(
        contentItemRepository: contentItems,
        summaryJobRepository: summaryJobs,
        idFactory: () => 'summary-note-1',
        clock: () => DateTime.utc(2026, 5, 8, 13),
      );

      final discussion = ContentItem(
        id: 'discussion-1',
        authorDid: 'did:plc:alice',
        mode: ContentMode.discussion,
        title: 'Public discussion',
        body: 'A long discussion body that needs a compact private summary.',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        createdAt: DateTime.utc(2026, 5, 8, 11),
        updatedAt: DateTime.utc(2026, 5, 8, 11),
        localOnly: false,
      );
      await contentItems.create(discussion);

      final pack = builder.forSummary(
        purpose: ContextPackPurpose.discussionSummary,
        createdByDid: 'did:plc:alice',
        sources: [discussion],
      );
      await contextPacks.create(pack);

      final result = await provider.complete(
        AiProviderRequest(
          task: 'discussion_summary',
          contextPack: jsonDecode(pack.snapshotJson) as Map<String, dynamic>,
          outputSchema: const {
            'type': 'object',
            'required': ['summary'],
          },
        ),
      );
      expect(
        result.structuredJson['summary'],
        contains('long discussion body'),
      );

      await summaryJobs.create(
        SummaryJob(
          id: 'summary-job-1',
          requestedByDid: 'did:plc:alice',
          contextPackId: pack.id,
          providerConfigId: 'manual-provider',
          summaryType: 'discussion',
          status: SummaryJobStatus.queued,
          createdAt: DateTime.utc(2026, 5, 8, 12),
          updatedAt: DateTime.utc(2026, 5, 8, 12),
        ),
      );
      await summaryJobs.markCompleted(
        'summary-job-1',
        resultJson: jsonEncode(result.structuredJson),
        completedAt: DateTime.utc(2026, 5, 8, 12, 30),
      );

      final note = await summaryService.saveSummaryAsPrivateNote(
        summaryJobId: 'summary-job-1',
        authorDid: 'did:plc:alice',
        title: 'Discussion summary',
      );

      expect(note.mode, ContentMode.note);
      expect(note.visibility, ContentVisibility.private);
      expect(note.localOnly, isTrue);
      expect(note.body, contains('long discussion body'));
    },
  );
}
