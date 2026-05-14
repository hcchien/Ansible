import '../entities/messenger_entities.dart';

abstract class MessengerRepository {
  Future<void> upsertLocalDevice(MessengerDeviceRecord device);

  Future<void> upsertRemoteDevice(MessengerDeviceRecord device);

  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys);

  Future<void> markPreKeyPublished(String deviceId, int preKeyId);

  Future<void> saveSession(MessengerSessionRecord session);

  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  );

  Future<void> saveMessage(MessengerMessageRecord message);

  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  );

  Future<void> saveMailboxCursor(String localDeviceId, String cursor);
}
