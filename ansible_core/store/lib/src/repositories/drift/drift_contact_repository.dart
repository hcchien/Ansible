import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/contact_entities.dart' as entity;
import '../contact_repository.dart';

class DriftContactRepository implements ContactRepository {
  DriftContactRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> upsertContact(entity.ContactRecord contact) {
    return _db
        .into(_db.contactRecords)
        .insertOnConflictUpdate(
          ContactRecordsCompanion.insert(
            subjectDid: contact.subjectDid,
            handle: Value(contact.handle),
            displayName: Value(contact.displayName),
            localAlias: Value(contact.localAlias),
            avatarUrl: Value(contact.avatarUrl),
            relationship: Value(contact.relationship.name),
            source: Value(contact.source),
            trustState: Value(contact.trustState.name),
            messengerAvailability: Value(contact.messengerAvailability.name),
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt,
            lastResolvedAt: Value(contact.lastResolvedAt),
          ),
        );
  }

  @override
  Future<entity.ContactRecord?> contactForDid(String subjectDid) async {
    final row = await (_db.select(
      _db.contactRecords,
    )..where((table) => table.subjectDid.equals(subjectDid))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<entity.ContactRecord?> contactForHandle(String handle) async {
    final row = await (_db.select(
      _db.contactRecords,
    )..where((table) => table.handle.equals(handle))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<List<entity.ContactRecord>> listContacts() async {
    final rows =
        await (_db.select(_db.contactRecords)..orderBy([
              (table) => OrderingTerm.asc(table.localAlias),
              (table) => OrderingTerm.asc(table.displayName),
              (table) => OrderingTerm.asc(table.handle),
              (table) => OrderingTerm.asc(table.subjectDid),
            ]))
            .get();
    return rows.map(_map).toList(growable: false);
  }

  @override
  Future<entity.ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  }) async {
    final existing = await contactForHandle(handle);
    if (existing == null) {
      final contact = entity.ContactRecord(
        subjectDid: resolvedDid,
        handle: handle,
        trustState: entity.ContactTrustState.known,
        createdAt: resolvedAt,
        updatedAt: resolvedAt,
        lastResolvedAt: resolvedAt,
      );
      await upsertContact(contact);
      return contact;
    }

    if (existing.subjectDid != resolvedDid) {
      final changed = existing.copyWith(
        trustState: entity.ContactTrustState.changed,
        updatedAt: resolvedAt,
        lastResolvedAt: resolvedAt,
      );
      await upsertContact(changed);
      return changed;
    }

    final refreshed = existing.copyWith(
      trustState: entity.ContactTrustState.known,
      updatedAt: resolvedAt,
      lastResolvedAt: resolvedAt,
    );
    await upsertContact(refreshed);
    return refreshed;
  }

  entity.ContactRecord _map(ContactRecord row) {
    return entity.ContactRecord(
      subjectDid: row.subjectDid,
      handle: row.handle,
      displayName: row.displayName,
      localAlias: row.localAlias,
      avatarUrl: row.avatarUrl,
      relationship: entity.ContactRelationship.parse(row.relationship),
      source: row.source,
      trustState: entity.ContactTrustState.parse(row.trustState),
      messengerAvailability: entity.MessengerAvailability.parse(
        row.messengerAvailability,
      ),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastResolvedAt: row.lastResolvedAt,
    );
  }
}
