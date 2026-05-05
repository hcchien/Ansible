import 'dart:convert';

import 'package:ansible_sync/ansible_sync.dart';
import 'package:test/test.dart';

void main() {
  group('FollowInboxController', () {
    test('rejects malformed follow without object', () async {
      final controller = FollowInboxController();
      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/follow/1',
        'type': 'Follow',
        'actor': 'https://remote.example/users/alice',
      });

      expect(response.statusCode, 400);
      expect(
        jsonDecode(await response.readAsString())['error'],
        'invalid_follow_activity',
      );
    });
  });
}
