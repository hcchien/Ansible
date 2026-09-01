import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/messenger_entities.dart' as entity;
import '../messenger_repository.dart';

class DriftMessengerRepository
    implements
        MessengerRepository,
        MessengerPreKeyLifecycleRepository,
        MessengerRemoteDeviceTrustRepository {
  DriftMessengerRepository(this._db);

  final AppDatabase _db;

  @override
  Future<entity.MessengerDeviceRecord?> localDeviceForSubject(
    String subjectDid,
  ) async {
    final row =
        await (_db.select(_db.messengerDevices)
              ..where(
                (table) =>
                    table.subjectDid.equals(subjectDid) &
                    table.isLocal.equals(true),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _mapDevice(row);
  }

  @override
  Future<void> upsertLocalDevice(entity.MessengerDeviceRecord device) async {
    await _upsertDevice(device.copyWith(isLocal: true));
  }

  @override
  Future<void> upsertRemoteDevice(entity.MessengerDeviceRecord device) async {
    await _upsertDevice(device.copyWith(isLocal: false));
  }

  @override
  Future<entity.MessengerDeviceRecord?> remoteDeviceById(
    String deviceId,
  ) async {
    final row =
        await (_db.select(_db.messengerDevices)
              ..where(
                (table) =>
                    table.deviceId.equals(deviceId) &
                    table.isLocal.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _mapDevice(row);
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
  Future<List<entity.MessengerPreKeyRecord>> unpublishedPreKeys(
    String deviceId,
  ) async {
    final rows =
        await (_db.select(_db.messengerPreKeys)
              ..where(
                (table) =>
                    table.deviceId.equals(deviceId) &
                    table.publishedAt.isNull() &
                    table.consumedAt.isNull(),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.preKeyId)]))
            .get();
    return rows.map(_mapPreKey).toList();
  }

  @override
  Future<List<entity.MessengerPreKeyRecord>> unconsumedPreKeys(
    String deviceId,
  ) async {
    final rows =
        await (_db.select(_db.messengerPreKeys)
              ..where(
                (table) =>
                    table.deviceId.equals(deviceId) & table.consumedAt.isNull(),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.preKeyId)]))
            .get();
    return rows.map(_mapPreKey).toList(growable: false);
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
  Future<void> markPreKeyConsumed(String deviceId, int preKeyId) async {
    await (_db.update(_db.messengerPreKeys)..where(
          (table) =>
              table.deviceId.equals(deviceId) & table.preKeyId.equals(preKeyId),
        ))
        .write(
          MessengerPreKeysCompanion(consumedAt: Value(DateTime.now().toUtc())),
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
  Future<List<entity.MessengerConversationRecord>> conversationList() async {
    final rows =
        await (_db.select(_db.messengerConversations)..orderBy([
              (table) => OrderingTerm.desc(table.lastMessageAt),
              (table) => OrderingTerm.desc(table.updatedAt),
            ]))
            .get();
    return rows.map(_mapConversation).toList(growable: false);
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
  Future<String?> mailboxCursorFor(String localDeviceId) async {
    final row =
        await (_db.select(_db.messengerMailboxCursors)
              ..where((table) => table.localDeviceId.equals(localDeviceId)))
            .getSingleOrNull();
    return row?.cursor;
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

  entity.MessengerDeviceRecord _mapDevice(MessengerDevice row) {
    return entity.MessengerDeviceRecord(
      subjectDid: row.subjectDid,
      deviceId: row.deviceId,
      identityKeyPublic: row.identityKeyPublic,
      identityKeyPrivateRef: row.identityKeyPrivateRef,
      isLocal: row.isLocal,
      signedPreKeyId: row.signedPreKeyId,
      signedPreKeyPublic: row.signedPreKeyPublic,
      signedPreKeyPrivateRef: row.signedPreKeyPrivateRef,
      signedPreKeySignature: row.signedPreKeySignature,
      bindingJson: row.bindingJson,
      bindingSignature: row.bindingSignature,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  entity.MessengerPreKeyRecord _mapPreKey(MessengerPreKey row) {
    return entity.MessengerPreKeyRecord(
      deviceId: row.deviceId,
      preKeyId: row.preKeyId,
      publicKey: row.publicKey,
      privateKeyRef: row.privateKeyRef,
      createdAt: row.createdAt,
      publishedAt: row.publishedAt,
      consumedAt: row.consumedAt,
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

  entity.MessengerConversationRecord _mapConversation(
    MessengerConversation row,
  ) {
    return entity.MessengerConversationRecord(
      conversationId: row.conversationId,
      peerDid: row.peerDid,
      title: row.title,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastMessageAt: row.lastMessageAt,
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
