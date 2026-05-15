import 'package:ansible_node/services/contact_source_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncs accepted user follows into contact records', () async {
    final follows = InMemoryFollowRepository();
    final contacts = _FakeContactRepository();
    final now = DateTime.utc(2026, 5, 15);
    final service = ContactSourceSyncService(
      followRepository: follows,
      contactRepository: contacts,
      now: () => now,
    );

    await follows.upsertTarget(
      FollowTarget(
        targetId: 'target-bob',
        targetType: FollowTargetType.user,
        canonicalUri: 'https://relay.example/users/bob',
        displayName: 'Bob',
        handle: 'bob.elix.app',
        did: 'did:plc:bob',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await follows.upsertEdge(
      FollowEdge(
        followId: 'follow-bob',
        followerDid: 'did:plc:alice',
        targetId: 'target-bob',
        targetType: FollowTargetType.user,
        direction: FollowDirection.outbound,
        status: FollowStatus.accepted,
        visibility: FollowVisibility.localOnly,
        createdAt: now,
        updatedAt: now,
        acceptedAt: now,
      ),
    );

    final synced = await service.syncForIdentity('did:plc:alice');

    expect(synced, 1);
    final contact = await contacts.contactForDid('did:plc:bob');
    expect(contact!.displayName, 'Bob');
    expect(contact.handle, 'bob.elix.app');
    expect(contact.relationship, ContactRelationship.following);
    expect(contact.source, 'follow');
    expect(contact.trustState, ContactTrustState.known);
    expect(contact.lastResolvedAt, now);
  });

  test('preserves local aliases when refreshing profile data', () async {
    final follows = InMemoryFollowRepository();
    final contacts = _FakeContactRepository();
    final now = DateTime.utc(2026, 5, 15);
    await contacts.upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:bob',
        handle: 'old-bob.elix.app',
        displayName: 'Old Bob',
        localAlias: '設計夥伴',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
    );
    await follows.upsertTarget(
      FollowTarget(
        targetId: 'target-bob',
        targetType: FollowTargetType.user,
        displayName: 'Bob Chen',
        handle: 'bob.elix.app',
        did: 'did:plc:bob',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await follows.upsertEdge(
      FollowEdge(
        followId: 'follow-bob',
        followerDid: 'did:plc:alice',
        targetId: 'target-bob',
        targetType: FollowTargetType.user,
        direction: FollowDirection.outbound,
        status: FollowStatus.accepted,
        visibility: FollowVisibility.localOnly,
        createdAt: now,
        updatedAt: now,
        acceptedAt: now,
      ),
    );

    await ContactSourceSyncService(
      followRepository: follows,
      contactRepository: contacts,
      now: () => now,
    ).syncForIdentity('did:plc:alice');

    final contact = await contacts.contactForDid('did:plc:bob');
    expect(contact!.localAlias, '設計夥伴');
    expect(contact.label, '設計夥伴');
    expect(contact.displayName, 'Bob Chen');
    expect(contact.handle, 'bob.elix.app');
  });

  test('syncs messenger conversation peers into contact records', () async {
    final follows = InMemoryFollowRepository();
    final contacts = _FakeContactRepository();
    final now = DateTime.utc(2026, 5, 15);
    final messenger = _FakeMessengerRepository([
      MessengerConversationRecord(
        conversationId: 'conversation-carol',
        peerDid: 'did:plc:carol',
        title: 'Carol',
        createdAt: now,
        updatedAt: now,
        lastMessageAt: now,
      ),
    ]);

    final synced = await ContactSourceSyncService(
      followRepository: follows,
      contactRepository: contacts,
      messengerRepository: messenger,
      now: () => now,
    ).syncForIdentity('did:plc:alice');

    expect(synced, 1);
    final contact = await contacts.contactForDid('did:plc:carol');
    expect(contact!.label, 'Carol');
    expect(contact.relationship, ContactRelationship.conversation);
    expect(contact.source, 'conversation');
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
    throw UnimplementedError();
  }

  @override
  Future<void> upsertContact(ContactRecord contact) async {
    _contactsByDid[contact.subjectDid] = contact;
  }
}

class _FakeMessengerRepository implements MessengerRepository {
  _FakeMessengerRepository(this._conversations);

  final List<MessengerConversationRecord> _conversations;

  @override
  Future<List<MessengerConversationRecord>> conversationList() async {
    return _conversations;
  }

  @override
  Future<MessengerDeviceRecord?> localDeviceForSubject(String subjectDid) {
    throw UnimplementedError();
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) {
    throw UnimplementedError();
  }

  @override
  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<String?> mailboxCursorFor(String localDeviceId) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveMessage(MessengerMessageRecord message) {
    throw UnimplementedError();
  }

  @override
  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveSession(MessengerSessionRecord session) {
    throw UnimplementedError();
  }

  @override
  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertLocalDevice(MessengerDeviceRecord device) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertRemoteDevice(MessengerDeviceRecord device) {
    throw UnimplementedError();
  }
}
