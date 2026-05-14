import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('stores contacts and prefers local alias for labels', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftContactRepository(db);

    final now = DateTime.utc(2026, 5, 14);
    await repo.upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:alice123456789',
        handle: 'alice.elix.app',
        displayName: 'Alice',
        localAlias: '設計夥伴 Alice',
        relationship: ContactRelationship.manual,
        source: 'manual',
        trustState: ContactTrustState.known,
        createdAt: now,
        updatedAt: now,
        lastResolvedAt: now,
      ),
    );

    final contact = await repo.contactForDid('did:plc:alice123456789');
    expect(contact!.label, '設計夥伴 Alice');
    expect(contact.handle, 'alice.elix.app');

    final contacts = await repo.listContacts();
    expect(contacts.single.subjectDid, 'did:plc:alice123456789');
  });

  test(
    'detects handle identity changes without overwriting DID silently',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftContactRepository(db);
      final now = DateTime.utc(2026, 5, 14);

      await repo.upsertContact(
        ContactRecord(
          subjectDid: 'did:plc:old',
          handle: 'alice.elix.app',
          trustState: ContactTrustState.known,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await repo.recordHandleResolution(
        handle: 'alice.elix.app',
        resolvedDid: 'did:plc:new',
        resolvedAt: now.add(const Duration(minutes: 1)),
      );

      expect(result.trustState, ContactTrustState.changed);
      expect(
        (await repo.contactForDid('did:plc:old'))!.trustState,
        ContactTrustState.changed,
      );
      expect(await repo.contactForDid('did:plc:new'), isNull);
    },
  );
}
