import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('AppDatabase downgrade guard', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ansible_downgrade_test');
      dbFile = File('${tempDir.path}/ansible.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('opening a database written by a NEWER schema fails clearly', () async {
      // Simulate a DB written by a future build: create it, then bump the stored
      // schema (user_version) well above what this build supports.
      final seed = AppDatabase(NativeDatabase(dbFile));
      // Force the migration to run so the file exists and is initialized.
      await seed.customStatement('PRAGMA user_version = 9999');
      await seed.close();

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(() async {
        await db.close();
      });

      // Any query triggers beforeOpen, which must reject the downgrade.
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<DatabaseDowngradeError>()),
      );
    });

    test('opening a same-version database succeeds', () async {
      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(() async {
        await db.close();
      });

      // Should open and run a trivial query without throwing.
      final rows = await db.customSelect('SELECT 1 AS one').get();
      expect(rows, isNotEmpty);
    });
  });
}
