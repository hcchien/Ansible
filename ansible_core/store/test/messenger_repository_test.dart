import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('stores devices, sessions, conversations, and messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftMessengerRepository(db);

    await repo.upsertLocalDevice(
      MessengerDeviceRecord(
        subjectDid: 'did:plc:alice',
        deviceId: 'msgdev_alice',
        identityKeyPublic: 'alice_identity_public',
        identityKeyPrivateRef: 'secure:msgdev_alice',
        createdAt: DateTime.utc(2026, 5, 14),
      ),
    );

    await repo.saveSession(
      MessengerSessionRecord(
        localDeviceId: 'msgdev_alice',
        remoteDid: 'did:plc:bob',
        remoteDeviceId: 'msgdev_bob',
        sessionState: 'serialized-session',
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    );

    await repo.saveMessage(
      MessengerMessageRecord(
        messageId: 'msg_test',
        conversationId: 'did:plc:bob',
        direction: MessengerMessageDirection.outbound,
        status: MessengerMessageStatus.sent,
        plaintext: 'hello bob',
        ciphertextType: 'pre_key_signal_message',
        createdAt: DateTime.utc(2026, 5, 14),
      ),
    );

    final messages = await repo.messagesForConversation('did:plc:bob');
    expect(messages.single.plaintext, 'hello bob');
    expect(messages.single.status, MessengerMessageStatus.sent);
  });
}
