import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('content lineage schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('database exposes content lineage and AI assistance tables', () {
      final tableNames = db.allTables.map((table) => table.actualTableName);

      expect(tableNames, contains('content_items'));
      expect(tableNames, contains('murmur_metadata'));
      expect(tableNames, contains('note_metadata'));
      expect(tableNames, contains('post_metadata'));
      expect(tableNames, contains('discussion_metadata'));
      expect(tableNames, contains('content_relations'));
      expect(tableNames, contains('transformation_jobs'));
      expect(tableNames, contains('context_packs'));
      expect(tableNames, contains('summary_jobs'));
      expect(tableNames, contains('ai_provider_configs'));
    });
  });
}
