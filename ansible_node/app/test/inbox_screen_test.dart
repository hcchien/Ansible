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
