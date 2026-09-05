import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('v36 adds local mention references without replacing posts', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'ansible_mentions_migration_test',
    );
    final dbFile = File('${tempDir.path}/ansible.db');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final seed = AppDatabase(NativeDatabase(dbFile));
    await seed.customSelect('SELECT 1').get();
    await seed.customStatement('ALTER TABLE posts DROP COLUMN mentions_json');
    await seed.customStatement("""
      INSERT INTO boards (board_id, slug, title, created_at, updated_at)
      VALUES ('board-1', 'general', 'General', 0, 0)
    """);
    await seed.customStatement("""
      INSERT INTO threads (thread_id, board_id, title, author_id, created_at, updated_at)
      VALUES ('thread-1', 'board-1', 'Mentions', 'did:elix:author', 0, 0)
    """);
    await seed.customStatement("""
      INSERT INTO posts (
        post_id, thread_id, board_id, author_id, content,
        created_at, updated_at, last_edit_at
      ) VALUES (
        'post-1', 'thread-1', 'board-1', 'did:elix:author', 'Hello @Alice',
        0, 0, 0
      )
    """);
    await seed.customStatement('PRAGMA user_version = 35');
    await seed.close();

    final migrated = AppDatabase(NativeDatabase(dbFile));
    addTearDown(migrated.close);
    final post = await DriftPostRepository(migrated).getById('post-1');

    expect(post?.content, 'Hello @Alice');
    expect(post?.mentions, isEmpty);
    final columns = await migrated
        .customSelect("SELECT name FROM pragma_table_info('posts')")
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('mentions_json'),
    );
  });
}
