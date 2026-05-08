import 'package:ansible_vc/src/lexicon_record.dart';
import 'package:test/test.dart';

void main() {
  group('content lineage Lexicon records', () {
    test('serializes murmur record', () {
      final json = const LexiconMurmur(
        text: 'Quick thought',
        createdAt: '2026-05-06T10:00:00.000Z',
        tone: 'intuition',
        sourceType: 'typed',
        langs: ['zh-TW'],
      ).toJson();

      expect(json[r'$type'], 'io.trisaura.murmur');
      expect(json['text'], 'Quick thought');
      expect(json['tone'], 'intuition');
      expect(json['sourceType'], 'typed');
      expect(json['langs'], ['zh-TW']);
      expect(json['createdAt'], '2026-05-06T10:00:00.000Z');
    });

    test('serializes note record without private visibility', () {
      final json = const LexiconNote(
        body: 'Structured note body',
        visibility: 'unlisted',
        createdAt: '2026-05-06T10:10:00.000Z',
        updatedAt: '2026-05-06T10:20:00.000Z',
        title: 'Note title',
        summary: 'Short summary',
      ).toJson();

      expect(json[r'$type'], 'io.trisaura.note');
      expect(json['title'], 'Note title');
      expect(json['body'], 'Structured note body');
      expect(json['visibility'], 'unlisted');
      expect(json['summary'], 'Short summary');
    });

    test('serializes discussion record', () {
      final json = const LexiconDiscussion(
        title: 'Public discussion',
        body: 'Opening context',
        discussionShape: 'thread',
        participationPolicy: 'comment',
        forkPolicy: 'allowed',
        consensusState: 'none',
        createdAt: '2026-05-06T10:30:00.000Z',
        updatedAt: '2026-05-06T10:30:00.000Z',
        boardId: 'board-1',
      ).toJson();

      expect(json[r'$type'], 'io.trisaura.discussion');
      expect(json['title'], 'Public discussion');
      expect(json['discussionShape'], 'thread');
      expect(json['participationPolicy'], 'comment');
      expect(json['forkPolicy'], 'allowed');
      expect(json['consensusState'], 'none');
      expect(json['boardId'], 'board-1');
    });

    test('serializes content relation record', () {
      final json = const LexiconContentRelation(
        from: 'at://did:plc:alice/io.trisaura.discussion/r1',
        to: 'at://did:plc:alice/io.trisaura.note/r2',
        relationType: 'projected_from',
        createdAt: '2026-05-06T10:31:00.000Z',
      ).toJson();

      expect(json[r'$type'], 'io.trisaura.contentRelation');
      expect(json['from'], startsWith('at://did:plc:alice/'));
      expect(json['to'], contains('/io.trisaura.note/'));
      expect(json['relationType'], 'projected_from');
    });

    test('serializes transformation record', () {
      final json = const LexiconTransformation(
        sourceRefs: ['at://did:plc:alice/io.trisaura.murmur/r1'],
        targetRef: 'at://did:plc:alice/io.trisaura.note/r2',
        targetMode: 'note',
        providerType: 'manual',
        status: 'accepted',
        createdAt: '2026-05-06T10:15:00.000Z',
        completedAt: '2026-05-06T10:16:00.000Z',
      ).toJson();

      expect(json[r'$type'], 'io.trisaura.transformation');
      expect(json['sourceRefs'], hasLength(1));
      expect(json['targetMode'], 'note');
      expect(json['providerType'], 'manual');
      expect(json['status'], 'accepted');
      expect(json.containsKey('inputSnapshot'), isFalse);
      expect(json.containsKey('outputSnapshot'), isFalse);
    });

    test('serializes projection record', () {
      final json = const LexiconProjection(
        source: 'at://did:plc:alice/io.trisaura.note/r2',
        target: 'at://did:plc:alice/io.trisaura.discussion/r3',
        projectedExcerpt: 'Excerpt',
        participationPolicy: 'comment',
        ownershipTransferAcknowledged: true,
        createdAt: '2026-05-06T10:31:00.000Z',
      ).toJson();

      expect(json[r'$type'], 'io.trisaura.projection');
      expect(json['source'], contains('/io.trisaura.note/'));
      expect(json['target'], contains('/io.trisaura.discussion/'));
      expect(json['ownershipTransferAcknowledged'], isTrue);
    });
  });
}
