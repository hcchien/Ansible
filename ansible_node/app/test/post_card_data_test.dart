import 'package:ansible_node/screens/home/post_card.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment count excludes the opening post', () {
    final now = DateTime.utc(2026, 7, 17);
    Post post(String id) => Post(
      id: id,
      threadId: 'thread-1',
      boardId: 'board-1',
      authorId: 'did:elix:alice',
      content: id,
      createdAt: now,
      updatedAt: now,
      lastEditAt: now,
    );

    expect(replyCountForPosts(const []), 0);
    expect(replyCountForPosts([post('op')]), 0);
    expect(replyCountForPosts([post('op'), post('reply')]), 1);
  });
}
