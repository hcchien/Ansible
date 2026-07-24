import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('v31 removes only legacy Ed25519 publication delivery state', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'ansible_p256_migration_test',
    );
    final dbFile = File('${tempDir.path}/ansible.db');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final seed = AppDatabase(NativeDatabase(dbFile));
    await seed.customSelect('SELECT 1').get();
    await seed.customStatement(
      "INSERT INTO publication_intents ("
      "intent_id, author_did, content_item_id, action, visibility, "
      "distribution_preference, status, signature_scheme"
      ") VALUES "
      "('legacy', 'did:elix:legacy', 'content-kept', 'create', 'public', "
      "'relay', 'complete', 'ed25519'), "
      "('current', 'did:elix:current', 'content-current', 'create', 'public', "
      "'relay', 'pending', 'p256-sha256')",
    );
    await seed.customStatement(
      "INSERT INTO publication_targets ("
      "target_id, intent_id, protocol, endpoint, status"
      ") VALUES "
      "('legacy-target', 'legacy', 'activitypub', 'https://legacy.test', "
      "'published'), "
      "('current-target', 'current', 'activitypub', 'https://current.test', "
      "'pending')",
    );
    await seed.customStatement('PRAGMA user_version = 30');
    await seed.close();

    final migrated = AppDatabase(NativeDatabase(dbFile));
    addTearDown(migrated.close);

    final intents = await migrated
        .customSelect(
          'SELECT intent_id, signature_scheme FROM publication_intents '
          'ORDER BY intent_id',
        )
        .get();
    final targets = await migrated
        .customSelect(
          'SELECT target_id, intent_id FROM publication_targets '
          'ORDER BY target_id',
        )
        .get();

    expect(intents.map((row) => row.read<String>('intent_id')).toList(), [
      'current',
    ]);
    expect(intents.single.read<String>('signature_scheme'), 'p256-sha256');
    expect(targets.map((row) => row.read<String>('target_id')).toList(), [
      'current-target',
    ]);
  });
}
