import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/messenger_entities.dart' as entity;
import '../messenger_repository.dart';

class DriftMessengerRepository implements MessengerRepository {
  DriftMessengerRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> upsertLocalDevice(entity.MessengerDeviceRecord device) async {
    await _upsertDevice(device.copyWith(isLocal: true));
  }

  @override
  Future<void> upsertRemoteDevice(entity.MessengerDeviceRecord device) async {
    await _upsertDevice(device.copyWith(isLocal: false));
  }

  @override
  Future<void> savePreKeys(List<entity.MessengerPreKeyRecord> preKeys) async {
    await _db.batch((batch) {
      for (final preKey in preKeys) {
        batch.insert(
          _db.messengerPreKeys,
          MessengerPreKeysCompanion.insert(
            deviceId: preKey.deviceId,
            preKeyId: preKey.preKeyId,
            publicKey: preKey.publicKey,
            privateKeyRef: Value(preKey.privateKeyRef),
            createdAt: preKey.createdAt,
            publishedAt: Value(preKey.publishedAt),
            consumedAt: Value(preKey.consumedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) async {
    await (_db.update(_db.messengerPreKeys)..where(
          (table) =>
              table.deviceId.equals(deviceId) & table.preKeyId.equals(preKeyId),
        ))
        .write(
          MessengerPreKeysCompanion(publishedAt: Value(DateTime.now().toUtc())),
        );
  }

  @override
  Future<void> saveSession(entity.MessengerSessionRecord session) async {
    await _db
        .into(_db.messengerSessions)
        .insertOnConflictUpdate(
          MessengerSessionsCompanion.insert(
            localDeviceId: session.localDeviceId,
            remoteDeviceId: session.remoteDeviceId,
            remoteDid: session.remoteDid,
            sessionState: session.sessionState,
            updatedAt: session.updatedAt,
          ),
        );
  }

  @override
  Future<entity.MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  ) async {
    final row =
        await (_db.select(_db.messengerSessions)..where(
              (table) =>
                  table.localDeviceId.equals(localDeviceId) &
                  table.remoteDeviceId.equals(remoteDeviceId),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapSession(row);
  }

  @override
  Future<void> saveMessage(entity.MessengerMessageRecord message) async {
    await _db.transaction(() async {
      await _db
          .into(_db.messengerConversations)
          .insertOnConflictUpdate(
            MessengerConversationsCompanion.insert(
              conversationId: message.conversationId,
              peerDid: message.conversationId,
              createdAt: message.createdAt,
              updatedAt: message.updatedAt ?? message.createdAt,
              lastMessageAt: Value(message.createdAt),
            ),
          );

      await _db
          .into(_db.messengerMessages)
          .insertOnConflictUpdate(
            MessengerMessagesCompanion.insert(
              messageId: message.messageId,
              conversationId: message.conversationId,
              direction: message.direction.name,
              status: message.status.name,
              plaintext: Value(message.plaintext),
              ciphertextType: Value(message.ciphertextType),
              ciphertext: Value(message.ciphertext),
              createdAt: message.createdAt,
              updatedAt: Value(message.updatedAt),
            ),
          );
    });
  }

  @override
  Future<List<entity.MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) async {
    final rows =
        await (_db.select(_db.messengerMessages)
              ..where((table) => table.conversationId.equals(conversationId))
              ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]))
            .get();
    return rows.map(_mapMessage).toList();
  }

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) async {
    await _db
        .into(_db.messengerMailboxCursors)
        .insertOnConflictUpdate(
          MessengerMailboxCursorsCompanion.insert(
            localDeviceId: localDeviceId,
            cursor: cursor,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> _upsertDevice(entity.MessengerDeviceRecord device) async {
    await _db
        .into(_db.messengerDevices)
        .insertOnConflictUpdate(
          MessengerDevicesCompanion.insert(
            deviceId: device.deviceId,
            subjectDid: device.subjectDid,
            identityKeyPublic: device.identityKeyPublic,
            identityKeyPrivateRef: Value(device.identityKeyPrivateRef),
            isLocal: Value(device.isLocal),
            signedPreKeyId: Value(device.signedPreKeyId),
            signedPreKeyPublic: Value(device.signedPreKeyPublic),
            signedPreKeyPrivateRef: Value(device.signedPreKeyPrivateRef),
            signedPreKeySignature: Value(device.signedPreKeySignature),
            bindingJson: Value(device.bindingJson),
            bindingSignature: Value(device.bindingSignature),
            createdAt: device.createdAt,
            updatedAt: Value(device.updatedAt),
          ),
        );
  }

  entity.MessengerSessionRecord _mapSession(MessengerSession row) {
    return entity.MessengerSessionRecord(
      localDeviceId: row.localDeviceId,
      remoteDid: row.remoteDid,
      remoteDeviceId: row.remoteDeviceId,
      sessionState: row.sessionState,
      updatedAt: row.updatedAt,
    );
  }

  entity.MessengerMessageRecord _mapMessage(MessengerMessage row) {
    return entity.MessengerMessageRecord(
      messageId: row.messageId,
      conversationId: row.conversationId,
      direction: entity.MessengerMessageDirection.parse(row.direction),
      status: entity.MessengerMessageStatus.parse(row.status),
      plaintext: row.plaintext,
      ciphertextType: row.ciphertextType,
      ciphertext: row.ciphertext,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
