
import 'package:ansible_ap/ansible_ap.dart';
import 'package:test/test.dart';

void main() {
  group('AP Serialization', () {
    test('Note serializes correctly', () {
      final note = Note(
        id: 'https://example.com/note/1',
        content: 'Hello World',
        attributedTo: 'https://example.com/users/alice',
        to: ['https://www.w3.org/ns/activitystreams#Public'],
        context: ['https://www.w3.org/ns/activitystreams'],
      );

      final json = note.toJson();
      expect(json['type'], 'Note');
      expect(json['id'], 'https://example.com/note/1');
      expect(json['content'], 'Hello World');
      expect(json['@context'], ['https://www.w3.org/ns/activitystreams']);
    });

    test('Person serializes correctly', () {
      final person = Person(
        id: 'https://example.com/users/alice',
        preferredUsername: 'alice',
        inbox: 'https://example.com/users/alice/inbox',
        publicKey: {
          'id': 'https://example.com/users/alice#main-key',
          'owner': 'https://example.com/users/alice',
          'publicKeyPem': 'PEM_DATA'
        },
      );

      final json = person.toJson();
      expect(json['type'], 'Person');
      expect(json['preferredUsername'], 'alice');
      expect(json['publicKey']['owner'], 'https://example.com/users/alice');
    });

    test('Activity serializes correctly', () {
      final activity = Activity(
        type: 'Create',
        actor: 'https://example.com/users/alice',
        object: {
          'type': 'Note',
          'content': 'Foo',
        },
      );

      final json = activity.toJson();
      expect(json['type'], 'Create');
      expect(json['actor'], 'https://example.com/users/alice');
      expect(json['object']['content'], 'Foo');
    });

    test('Parses JSON back to object', () {
      final json = {
        'type': 'Note',
        'id': 'http://foo.com',
        'content': 'bar'
      };
      final note = Note.fromJson(json);
      expect(note.type, 'Note');
      expect(note.id, 'http://foo.com');
      expect(note.content, 'bar');
    });
  });
}
