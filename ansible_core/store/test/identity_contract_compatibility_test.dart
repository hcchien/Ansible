import 'dart:convert';
import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  test('local models retain canonical board and author DID fields offline', () {
    final cases = jsonDecode(
      File(
        '../../contracts/identity-resolution/v1/conformance/board-resolution.json',
      ).readAsStringSync(),
    ) as List<dynamic>;
    final board = (cases.first as Map<String, dynamic>)['boards'][0]
        as Map<String, dynamic>;

    final thread = Thread.fromJson({
      'id': 'thread-1',
      'board_id': board['id'],
      'title': 'Offline fixture',
      'authorDid': 'did:elix:5smknmtlodh7pomzg7iuibhfwq',
      'createdAt': '2026-07-25T00:00:00Z',
    });
    final post = Post.fromJson({
      'id': 'post-1',
      'threadId': thread.id,
      'board_id': board['id'],
      'authorDid': thread.authorId,
      'content': 'Offline reply',
      'createdAt': '2026-07-25T00:01:00Z',
    });

    expect(thread.boardId, '1');
    expect(thread.authorId, 'did:elix:5smknmtlodh7pomzg7iuibhfwq');
    expect(post.boardId, thread.boardId);
    expect(post.authorId, thread.authorId);
  });
}
