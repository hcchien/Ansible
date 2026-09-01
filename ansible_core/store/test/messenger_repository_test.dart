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
    final localDevice = await repo.localDeviceForSubject('did:plc:alice');
    expect(localDevice!.deviceId, 'msgdev_alice');

    await repo.savePreKeys([
      MessengerPreKeyRecord(
        deviceId: 'msgdev_alice',
        preKeyId: 1001,
        publicKey: 'pre_key_public',
        privateKeyRef: 'secure:pre_key_1001',
        createdAt: DateTime.utc(2026, 5, 14),
      ),
    ]);
    expect(await repo.unpublishedPreKeys('msgdev_alice'), hasLength(1));

    await repo.markPreKeyPublished('msgdev_alice', 1001);
    expect(await repo.unpublishedPreKeys('msgdev_alice'), isEmpty);

    await repo.saveSession(
      MessengerSessionRecord(
        localDeviceId: 'msgdev_alice',
        remoteDid: 'did:plc:bob',
        remoteDeviceId: 'msgdev_bob',
        protocolVersion: 'signal-reviewed-v2',
        sessionState: 'serialized-session',
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    );

    final session = await repo.sessionFor('msgdev_alice', 'msgdev_bob');
    expect(session!.protocolVersion, 'signal-reviewed-v2');

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

    final conversations = await repo.conversationList();
    expect(conversations.single.conversationId, 'did:plc:bob');
    expect(
      conversations.single.lastMessageAt?.toUtc(),
      DateTime.utc(2026, 5, 14),
    );

    expect(await repo.mailboxCursorFor('msgdev_alice'), isNull);
    await repo.saveMailboxCursor('msgdev_alice', 'cursor-2');
    expect(await repo.mailboxCursorFor('msgdev_alice'), 'cursor-2');
  });

  test('remote device id cannot overwrite a local device', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftMessengerRepository(db);

    await repo.upsertLocalDevice(
      MessengerDeviceRecord(
        subjectDid: 'did:plc:alice',
        deviceId: 'shared-device-id',
        identityKeyPublic: 'alice-public',
        identityKeyPrivateRef: 'secure:alice-private',
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    );

    await expectLater(
      repo.upsertRemoteDevice(
        MessengerDeviceRecord(
          subjectDid: 'did:plc:mallory',
          deviceId: 'shared-device-id',
          identityKeyPublic: 'mallory-public',
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ),
      throwsA(isA<MessengerDeviceIdCollision>()),
    );

    final local = await repo.localDeviceForSubject('did:plc:alice');
    expect(local, isNotNull);
    expect(local!.identityKeyPrivateRef, 'secure:alice-private');
  });
}
