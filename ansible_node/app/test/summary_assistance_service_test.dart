import 'package:ansible_node/services/ai/summary_assistance_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SummaryAssistanceService', () {
    test('saves completed summary as a private note', () async {
      final contentItems = InMemoryContentItemRepository();
      final summaryJobs = InMemorySummaryJobRepository();
      final service = SummaryAssistanceService(
        contentItemRepository: contentItems,
        summaryJobRepository: summaryJobs,
        idFactory: () => 'note-1',
        clock: () => DateTime.utc(2026, 5, 8, 12),
      );

      await summaryJobs.create(
        SummaryJob(
          id: 'summary-1',
          requestedByDid: 'did:plc:alice',
          contextPackId: 'context-1',
          providerConfigId: 'provider-1',
          summaryType: 'discussion',
          status: SummaryJobStatus.completed,
          resultJson: '{"summary":"Short private summary"}',
          createdAt: DateTime.utc(2026, 5, 8, 11),
          updatedAt: DateTime.utc(2026, 5, 8, 11),
          completedAt: DateTime.utc(2026, 5, 8, 11),
        ),
      );

      final note = await service.saveSummaryAsPrivateNote(
        summaryJobId: 'summary-1',
        authorDid: 'did:plc:alice',
        title: 'Discussion summary',
      );

      expect(note.mode, ContentMode.note);
      expect(note.visibility, ContentVisibility.private);
      expect(note.localOnly, isTrue);
      expect(note.body, 'Short private summary');
      expect(await contentItems.getById('note-1'), isNotNull);
    });
  });
}
