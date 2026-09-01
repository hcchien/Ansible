import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('v36 labels existing messenger sessions as legacy protocol', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'ansible_messenger_protocol_migration_test',
    );
    final dbFile = File('${tempDir.path}/ansible.db');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final seed = AppDatabase(NativeDatabase(dbFile));
    await seed.customSelect('SELECT 1').get();
    await seed.customStatement('DROP TABLE messenger_sessions');
    await seed.customStatement('''
      CREATE TABLE messenger_sessions (
        local_device_id TEXT NOT NULL,
        remote_device_id TEXT NOT NULL,
        remote_did TEXT NOT NULL,
        session_state TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (local_device_id, remote_device_id)
      )
    ''');
    await seed.customStatement('''
      INSERT INTO messenger_sessions (
        local_device_id,
        remote_device_id,
        remote_did,
        session_state,
        updated_at
      ) VALUES (
        'msgdev_alice',
        'msgdev_bob',
        'did:plc:bob',
        'legacy-state',
        1788192000
      )
    ''');
    await seed.customStatement('PRAGMA user_version = 35');
    await seed.close();

    final migrated = AppDatabase(NativeDatabase(dbFile));
    addTearDown(migrated.close);
    final session = await DriftMessengerRepository(
      migrated,
    ).sessionFor('msgdev_alice', 'msgdev_bob');

    expect(session, isNotNull);
    expect(session!.protocolVersion, 'signal-mvp-v1');
    expect(session.sessionState, 'legacy-state');
  });
}
