import '../entities/messenger_entities.dart';

abstract class MessengerRepository {
  Future<MessengerDeviceRecord?> localDeviceForSubject(String subjectDid);

  Future<void> upsertLocalDevice(MessengerDeviceRecord device);

  Future<void> upsertRemoteDevice(MessengerDeviceRecord device);

  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys);

  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(String deviceId);

  Future<void> markPreKeyPublished(String deviceId, int preKeyId);

  Future<void> saveSession(MessengerSessionRecord session);

  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  );

  Future<List<MessengerConversationRecord>> conversationList();

  Future<void> saveMessage(MessengerMessageRecord message);

  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  );

  Future<String?> mailboxCursorFor(String localDeviceId);

  Future<void> saveMailboxCursor(String localDeviceId, String cursor);
}

abstract interface class MessengerPreKeyLifecycleRepository {
  Future<List<MessengerPreKeyRecord>> allPreKeys(String deviceId);

  Future<List<MessengerPreKeyRecord>> unconsumedPreKeys(String deviceId);

  Future<void> markPreKeyConsumed(String deviceId, int preKeyId);
}

abstract interface class MessengerRemoteDeviceTrustRepository {
  Future<MessengerDeviceRecord?> deviceById(String deviceId);
}

abstract interface class MessengerMessageLookupRepository {
  Future<MessengerMessageRecord?> messageById(String messageId);
}

abstract interface class MessengerPendingOutboxRepository {
  Future<List<MessengerMessageRecord>> pendingOutboundMessages();
}

class MessengerDeviceIdCollision implements Exception {
  const MessengerDeviceIdCollision(this.deviceId);

  final String deviceId;

  @override
  String toString() => 'MessengerDeviceIdCollision($deviceId)';
}
