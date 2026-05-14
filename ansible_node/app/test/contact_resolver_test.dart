import 'package:ansible_node/services/contact_resolver.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves DID input into a local contact record', () async {
    final repo = _FakeContactRepository();
    final resolver = ContactResolver(
      repository: repo,
      now: () => DateTime.utc(2026, 5, 14),
    );

    final result = await resolver.resolveInput('did:plc:alice');

    expect(result.subjectDid, 'did:plc:alice');
    expect(result.label, startsWith('did:plc'));
    expect(
      (await repo.contactForDid('did:plc:alice'))!.subjectDid,
      'did:plc:alice',
    );
  });

  test('detects handle identity changes through repository result', () async {
    final repo = _FakeContactRepository();
    final resolver = ContactResolver(
      repository: repo,
      handleResolver: (handle) async => 'did:plc:new',
      now: () => DateTime.utc(2026, 5, 14),
    );
    await repo.upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:old',
        handle: 'alice.elix.app',
        trustState: ContactTrustState.known,
        createdAt: DateTime.utc(2026, 5, 14),
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    );

    final result = await resolver.resolveInput('alice.elix.app');

    expect(result.subjectDid, 'did:plc:old');
    expect(result.trustState, ContactTrustState.changed);
  });
}

class _FakeContactRepository implements ContactRepository {
  final Map<String, ContactRecord> _contactsByDid = {};

  @override
  Future<ContactRecord?> contactForDid(String subjectDid) async {
    return _contactsByDid[subjectDid];
  }

  @override
  Future<ContactRecord?> contactForHandle(String handle) async {
    for (final contact in _contactsByDid.values) {
      if (contact.handle == handle) return contact;
    }
    return null;
  }

  @override
  Future<List<ContactRecord>> listContacts() async {
    return _contactsByDid.values.toList(growable: false);
  }

  @override
  Future<ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  }) async {
    final existing = await contactForHandle(handle);
    if (existing == null) {
      final contact = ContactRecord(
        subjectDid: resolvedDid,
        handle: handle,
        trustState: ContactTrustState.known,
        createdAt: resolvedAt,
        updatedAt: resolvedAt,
        lastResolvedAt: resolvedAt,
      );
      await upsertContact(contact);
      return contact;
    }
    if (existing.subjectDid != resolvedDid) {
      final changed = existing.copyWith(
        trustState: ContactTrustState.changed,
        updatedAt: resolvedAt,
        lastResolvedAt: resolvedAt,
      );
      await upsertContact(changed);
      return changed;
    }
    final refreshed = existing.copyWith(
      trustState: ContactTrustState.known,
      updatedAt: resolvedAt,
      lastResolvedAt: resolvedAt,
    );
    await upsertContact(refreshed);
    return refreshed;
  }

  @override
  Future<void> upsertContact(ContactRecord contact) async {
    _contactsByDid[contact.subjectDid] = contact;
  }
}
