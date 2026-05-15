import 'package:ansible_node/screens/inbox_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inbox shows empty state instead of mock rows', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InboxScreen()));

    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('目前沒有收信'), findsOneWidget);
    expect(find.text('kr.'), findsNothing);
    expect(find.text('林下'), findsNothing);
    expect(find.text('週四讀書會'), findsNothing);
    expect(find.text('iPad mini'), findsNothing);
    expect(find.textContaining('patches'), findsNothing);
  });

  testWidgets('inbox renders conversation list from repository', (
    tester,
  ) async {
    final repository = _FakeMessengerRepository(
      conversations: [
        MessengerConversationRecord(
          conversationId: 'did:plc:bob',
          peerDid: 'did:plc:bob',
          createdAt: DateTime.utc(2026, 5, 14, 8),
          updatedAt: DateTime.utc(2026, 5, 14, 9),
          lastMessageAt: DateTime.utc(2026, 5, 14, 9),
        ),
      ],
      messages: {
        'did:plc:bob': [
          MessengerMessageRecord(
            messageId: 'msg_1',
            conversationId: 'did:plc:bob',
            direction: MessengerMessageDirection.inbound,
            status: MessengerMessageStatus.received,
            plaintext: 'hello from bob',
            createdAt: DateTime.utc(2026, 5, 14, 9),
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(repository: repository)),
    );
    await tester.pump();

    expect(find.text('did:plc:bob'), findsOneWidget);
    expect(find.text('hello from bob'), findsOneWidget);
    expect(find.text('目前沒有收信'), findsNothing);
  });

  testWidgets('inbox uses contact labels when available', (tester) async {
    final repository = _FakeMessengerRepository(
      conversations: [
        MessengerConversationRecord(
          conversationId: 'did:plc:bob',
          peerDid: 'did:plc:bob',
          createdAt: DateTime.utc(2026, 5, 14, 8),
          updatedAt: DateTime.utc(2026, 5, 14, 9),
          lastMessageAt: DateTime.utc(2026, 5, 14, 9),
        ),
      ],
    );
    final contacts = _FakeContactRepository({
      'did:plc:bob': ContactRecord(
        subjectDid: 'did:plc:bob',
        handle: 'bob.elix.app',
        displayName: 'Bob',
        createdAt: DateTime.utc(2026, 5, 14),
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(repository: repository, contactRepository: contacts),
      ),
    );
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('did:plc:bob'), findsNothing);
  });
}

class _FakeMessengerRepository implements MessengerRepository {
  _FakeMessengerRepository({
    this.conversations = const [],
    this.messages = const {},
  });

  final List<MessengerConversationRecord> conversations;
  final Map<String, List<MessengerMessageRecord>> messages;

  @override
  Future<List<MessengerConversationRecord>> conversationList() async {
    return conversations;
  }

  @override
  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) async {
    return messages[conversationId] ?? const [];
  }

  @override
  Future<MessengerDeviceRecord?> localDeviceForSubject(
    String subjectDid,
  ) async {
    return null;
  }

  @override
  Future<String?> mailboxCursorFor(String localDeviceId) async {
    return null;
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) async {}

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) async {}

  @override
  Future<void> saveMessage(MessengerMessageRecord message) async {}

  @override
  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys) async {}

  @override
  Future<void> saveSession(MessengerSessionRecord session) async {}

  @override
  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  ) async {
    return null;
  }

  @override
  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(
    String deviceId,
  ) async {
    return const [];
  }

  @override
  Future<void> upsertLocalDevice(MessengerDeviceRecord device) async {}

  @override
  Future<void> upsertRemoteDevice(MessengerDeviceRecord device) async {}
}

class _FakeContactRepository implements ContactRepository {
  _FakeContactRepository(this.contacts);

  final Map<String, ContactRecord> contacts;

  @override
  Future<ContactRecord?> contactForDid(String subjectDid) async {
    return contacts[subjectDid];
  }

  @override
  Future<ContactRecord?> contactForHandle(String handle) async {
    for (final contact in contacts.values) {
      if (contact.handle == handle) return contact;
    }
    return null;
  }

  @override
  Future<List<ContactRecord>> listContacts() async {
    return contacts.values.toList(growable: false);
  }

  @override
  Future<ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertContact(ContactRecord contact) async {
    contacts[contact.subjectDid] = contact;
  }
}
