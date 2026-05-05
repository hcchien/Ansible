import 'package:ansible_ap/ansible_ap.dart';
import 'package:test/test.dart';

void main() {
  group('FollowActivity', () {
    test('serializes user follow', () {
      final activity = FollowActivity.user(
        id: 'https://node.example/activities/follow/1',
        actor: 'did:key:local',
        object: 'https://remote.example/users/alice',
        published: DateTime.utc(2026, 5, 4),
      );

      expect(activity.toJson(), containsPair('type', 'Follow'));
      expect(activity.toJson(), containsPair('actor', 'did:key:local'));
      expect(
        activity.toJson(),
        containsPair('object', 'https://remote.example/users/alice'),
      );
    });

    test('serializes board follow extension', () {
      final activity = FollowActivity.board(
        id: 'https://node.example/activities/follow/board-1',
        actor: 'did:key:local',
        object: 'https://remote.example/boards/civic-tech',
        boardId: 'board-civic-tech',
        published: DateTime.utc(2026, 5, 4),
      );

      final json = activity.toJson();

      expect(json['type'], 'Follow');
      expect(json['trisAura:targetType'], 'board');
      expect(json['trisAura:boardId'], 'board-civic-tech');
    });

    test('parses inbound user follow', () {
      final activity = FollowActivity.fromJson({
        '@context': 'https://www.w3.org/ns/activitystreams',
        'id': 'https://node.example/activities/follow/1',
        'type': 'Follow',
        'actor': 'did:key:local',
        'object': 'https://remote.example/users/alice',
        'published': '2026-05-04T00:00:00.000Z',
      });

      expect(activity.id, 'https://node.example/activities/follow/1');
      expect(activity.actor, 'did:key:local');
      expect(activity.isBoardFollow, isFalse);
    });

    test('rejects malformed inbound activity', () {
      expect(
        () => FollowActivity.fromJson({
          'type': 'Follow',
          'actor': 'did:key:local',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('FollowResponseActivity', () {
    test('serializes accept activity with nested follow object', () {
      final follow = FollowActivity.user(
        id: 'https://node.example/activities/follow/1',
        actor: 'did:key:local',
        object: 'https://remote.example/users/alice',
        published: DateTime.utc(2026, 5, 4),
      );
      final accept = FollowResponseActivity.accept(
        id: 'https://remote.example/activities/accept/42',
        actor: 'https://remote.example/users/alice',
        object: follow,
        published: DateTime.utc(2026, 5, 4, 0, 0, 10),
      );

      final json = accept.toJson();

      expect(json['type'], 'Accept');
      expect(json['object'], isA<Map<String, dynamic>>());
      expect((json['object'] as Map<String, dynamic>)['type'], 'Follow');
      expect(json['to'], ['did:key:local']);
    });

    test('parses reject activity', () {
      final activity = FollowResponseActivity.fromJson({
        '@context': 'https://www.w3.org/ns/activitystreams',
        'id': 'https://remote.example/activities/reject/42',
        'type': 'Reject',
        'actor': 'https://remote.example/users/alice',
        'object': {
          'id': 'https://node.example/activities/follow/1',
          'type': 'Follow',
          'actor': 'did:key:local',
          'object': 'https://remote.example/users/alice',
          'published': '2026-05-04T00:00:00.000Z',
        },
        'published': '2026-05-04T00:00:10.000Z',
      });

      expect(activity.type, FollowResponseType.reject);
      expect(activity.object.actor, 'did:key:local');
    });

    test('parses response with minimal nested follow object', () {
      final activity = FollowResponseActivity.fromJson({
        '@context': 'https://www.w3.org/ns/activitystreams',
        'id': 'https://remote.example/activities/accept/42',
        'type': 'Accept',
        'actor': 'https://remote.example/users/alice',
        'object': {
          'id': 'https://node.example/activities/follow/1',
          'type': 'Follow',
          'actor': 'did:key:local',
          'object': 'https://remote.example/users/alice',
        },
        'published': '2026-05-04T00:00:10.000Z',
      });

      expect(activity.object.id, 'https://node.example/activities/follow/1');
      expect(activity.object.published, isNull);
    });
  });

  group('UndoFollowActivity', () {
    test('serializes undo follow activity', () {
      final follow = FollowActivity.user(
        id: 'https://node.example/activities/follow/1',
        actor: 'did:key:local',
        object: 'https://remote.example/users/alice',
        published: DateTime.utc(2026, 5, 4),
      );
      final undo = UndoFollowActivity(
        id: 'https://node.example/activities/undo/follow-1',
        actor: 'did:key:local',
        object: follow,
        published: DateTime.utc(2026, 5, 4, 0, 1),
      );

      final json = undo.toJson();

      expect(json['type'], 'Undo');
      expect(json['actor'], 'did:key:local');
      expect((json['object'] as Map<String, dynamic>)['type'], 'Follow');
    });

    test('rejects undo with non-follow object', () {
      expect(
        () => UndoFollowActivity.fromJson({
          'id': 'https://node.example/activities/undo/follow-1',
          'type': 'Undo',
          'actor': 'did:key:local',
          'object': {'type': 'Create'},
          'published': '2026-05-04T00:01:00.000Z',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
