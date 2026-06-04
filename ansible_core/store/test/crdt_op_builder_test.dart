import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('CrdtOpBuilder murmur/note', () {
    test('createMurmur builds a murmur op with a public distributable payload', () {
      final op = CrdtOpBuilder.createMurmur(
        authorDid: 'did:key:alice',
        entityId: 'murmur-1',
        text: 'a passing thought',
        tone: 'note',
        sourceType: 'typed',
      );

      expect(op.entityType, 'murmur');
      expect(op.opType, 'insert');
      expect(op.authorDid, 'did:key:alice');
      expect(op.entityId, 'murmur-1');

      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['mode'], 'murmur');
      expect(payload['body'], 'a passing thought');
      expect(payload['visibility'], 'public');
      expect(payload['tone'], 'note');
      expect(payload['sourceType'], 'typed');
      expect(payload.containsKey('createdAt'), isTrue);
      // Private metadata must never enter the op payload.
      expect(payload.containsKey('privateTagsJson'), isFalse);
    });

    test('createNote builds a note op carrying its visibility', () {
      final op = CrdtOpBuilder.createNote(
        authorDid: 'did:key:alice',
        entityId: 'note-1',
        body: 'a longer essay',
        title: 'On Things',
        visibility: 'unlisted',
      );

      expect(op.entityType, 'note');
      expect(op.opType, 'insert');

      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['mode'], 'note');
      expect(payload['body'], 'a longer essay');
      expect(payload['title'], 'On Things');
      expect(payload['visibility'], 'unlisted');
      expect(payload.containsKey('createdAt'), isTrue);
    });

    test('createMurmur accepts unlisted visibility', () {
      final op = CrdtOpBuilder.createMurmur(
        authorDid: 'did:key:alice',
        entityId: 'm2',
        text: 'hi',
        visibility: 'unlisted',
      );
      expect(CrdtOpBuilder.decodePayload(op.payload)['visibility'], 'unlisted');
    });
  });
}
