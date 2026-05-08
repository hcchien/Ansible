import 'package:ansible_node/services/ai/context_pack_builder.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContextPackBuilder', () {
    test('builds private transformation context from source content', () {
      final builder = ContextPackBuilder(
        idFactory: () => 'context-1',
        clock: () => DateTime.utc(2026, 5, 8, 12),
      );

      final pack = builder.forTransformation(
        purpose: ContextPackPurpose.murmurToNote,
        createdByDid: 'did:plc:alice',
        sources: [
          ContentItem(
            id: 'murmur-1',
            authorDid: 'did:plc:alice',
            mode: ContentMode.murmur,
            body: 'Private thought',
            status: ContentStatus.draft,
            visibility: ContentVisibility.private,
            createdAt: DateTime.utc(2026, 5, 8, 11),
            updatedAt: DateTime.utc(2026, 5, 8, 11),
          ),
        ],
      );

      expect(pack.id, 'context-1');
      expect(pack.purpose, ContextPackPurpose.murmurToNote);
      expect(pack.privacyLevel, ContextPrivacyLevel.containsPrivate);
      expect(pack.allowedRemote, isFalse);
      expect(pack.sourceRefsJson, contains('murmur-1'));
      expect(pack.snapshotJson, contains('Private thought'));
    });

    test('builds public summary context for discussions', () {
      final builder = ContextPackBuilder(
        idFactory: () => 'context-2',
        clock: () => DateTime.utc(2026, 5, 8, 12),
      );

      final pack = builder.forSummary(
        purpose: ContextPackPurpose.discussionSummary,
        createdByDid: 'did:plc:alice',
        sources: [
          ContentItem(
            id: 'discussion-1',
            authorDid: 'did:plc:alice',
            mode: ContentMode.discussion,
            body: 'Public discussion',
            status: ContentStatus.active,
            visibility: ContentVisibility.public,
            createdAt: DateTime.utc(2026, 5, 8, 11),
            updatedAt: DateTime.utc(2026, 5, 8, 11),
            localOnly: false,
          ),
        ],
      );

      expect(pack.privacyLevel, ContextPrivacyLevel.publicOnly);
      expect(pack.allowedRemote, isTrue);
    });
  });
}
