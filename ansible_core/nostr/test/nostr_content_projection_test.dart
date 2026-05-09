import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('ContentItem to Nostr projection', () {
    test('maps public murmurs to NIP-01 kind 1 short text notes', () {
      final draft = NostrContentProjection.projectContent(
        _content(
          id: 'murmur-1',
          mode: ContentMode.murmur,
          visibility: ContentVisibility.public,
          body: 'hello nostr',
        ),
        pubkey: 'a' * 64,
      );

      expect(draft.kind, 1);
      expect(draft.content, 'hello nostr');
      expect(draft.tags, isEmpty);
    });

    test('maps public notes to NIP-23 kind 30023 long-form events', () {
      final draft = NostrContentProjection.projectContent(
        _content(
          id: 'note-1',
          mode: ContentMode.note,
          visibility: ContentVisibility.public,
          title: 'Long note',
          body: 'long body',
          publishedAt: DateTime.fromMillisecondsSinceEpoch(
            1710000000000,
            isUtc: true,
          ),
        ),
        pubkey: 'a' * 64,
      );

      expect(draft.kind, 30023);
      expect(draft.content, 'long body');
      expect(
        draft.tags.map((tag) => tag.join('=')),
        containsAll(['d=note-1', 'title=Long note', 'published_at=1710000000']),
      );
    });

    test('rejects private content', () {
      expect(
        () => NostrContentProjection.projectContent(
          _content(
            id: 'private-note',
            mode: ContentMode.note,
            visibility: ContentVisibility.private,
            body: 'private',
          ),
          pubkey: 'a' * 64,
        ),
        throwsA(isA<NostrProjectionException>()),
      );
    });

    test('maps delete tombstones to NIP-09 kind 5 events', () {
      final draft = NostrContentProjection.projectDelete(
        contentId: 'note-1',
        priorEventId: 'b' * 64,
        pubkey: 'a' * 64,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(
          1710000000000,
          isUtc: true,
        ),
      );

      expect(draft.kind, 5);
      expect(draft.content, 'delete note-1');
      expect(draft.tags.map((tag) => tag.join('=')), contains('e=${'b' * 64}'));
    });

    test('maps accepted outbound Nostr follows to NIP-02 kind 3 contacts', () {
      final now = DateTime.fromMillisecondsSinceEpoch(
        1710000000000,
        isUtc: true,
      );
      final followedPubkey = 'c' * 64;

      final draft = NostrContentProjection.projectFollowList(
        pubkey: 'a' * 64,
        updatedAt: now,
        edges: [
          FollowEdge(
            followId: 'follow-1',
            followerDid: 'did:plc:alice',
            targetId: 'target-1',
            targetType: FollowTargetType.user,
            direction: FollowDirection.outbound,
            status: FollowStatus.accepted,
            visibility: FollowVisibility.federated,
            createdAt: now,
            updatedAt: now,
          ),
          FollowEdge(
            followId: 'follow-local',
            followerDid: 'did:plc:alice',
            targetId: 'target-local',
            targetType: FollowTargetType.user,
            direction: FollowDirection.outbound,
            status: FollowStatus.accepted,
            visibility: FollowVisibility.localOnly,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        targets: [
          FollowTarget(
            targetId: 'target-1',
            targetType: FollowTargetType.user,
            displayName: 'Alice',
            did: 'did:nostr:$followedPubkey',
            canonicalUri: 'wss://relay.example',
            createdAt: now,
            updatedAt: now,
          ),
          FollowTarget(
            targetId: 'target-local',
            targetType: FollowTargetType.user,
            displayName: 'Local',
            did: 'did:nostr:${'d' * 64}',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );

      expect(draft.kind, 3);
      expect(draft.content, '');
      expect(draft.tags.map((tag) => tag.join('=')), [
        'p=$followedPubkey=wss://relay.example=Alice',
      ]);
    });

    test('maps relay preferences to NIP-65 kind 10002 relay list metadata', () {
      final draft = NostrContentProjection.projectRelayList(
        pubkey: 'a' * 64,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          1710000000000,
          isUtc: true,
        ),
        relays: const [
          NostrRelayPreference(url: 'wss://read.example', read: true),
          NostrRelayPreference(url: 'wss://write.example', write: true),
          NostrRelayPreference(
            url: 'wss://both.example',
            read: true,
            write: true,
          ),
        ],
      );

      expect(draft.kind, 10002);
      expect(draft.tags.map((tag) => tag.join('=')), [
        'r=wss://read.example=read',
        'r=wss://write.example=write',
        'r=wss://both.example',
      ]);
    });
  });
}

ContentItem _content({
  required String id,
  required ContentMode mode,
  required ContentVisibility visibility,
  required String body,
  String? title,
  DateTime? publishedAt,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);
  return ContentItem(
    id: id,
    authorDid: 'did:plc:alice',
    mode: mode,
    title: title,
    body: body,
    status: ContentStatus.active,
    visibility: visibility,
    publishedAt: publishedAt,
    createdAt: now,
    updatedAt: now,
    localOnly: visibility == ContentVisibility.private,
  );
}
