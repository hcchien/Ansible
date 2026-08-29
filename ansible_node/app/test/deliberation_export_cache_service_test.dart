import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_node/services/deliberation_export_cache_service.dart';

void main() {
  test(
    'stores only the authorized export fields with local board scope',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 12));

      await DeliberationExportCacheService(db).save(
        localBoardId: 'local-board-1',
        title: 'Release cadence',
        export: {
          'export_id': 'export-1',
          'board_id': 'remote-board-99',
          'deliberation_id': 'deliberation-1',
          'view': 'pseudonymous_matrix',
          'expires_at': expiresAt.toIso8601String(),
          'manifest': {
            'dataset_digest': 'abc',
            'participant_identifiers': 'export_scoped_pseudonyms',
          },
          'report': {'participant_count': 15},
          'statements': [
            {'id': 's-1', 'text': 'Ship weekly'},
          ],
          'responses': [
            {
              'export_participant_id': 'person-1',
              'statement_id': 's-1',
              'stance': 'agree',
            },
          ],
        },
      );

      final row = await db.select(db.deliberationExports).getSingle();
      expect(row.boardId, 'local-board-1');
      expect(row.deliberationId, 'deliberation-1');
      expect(jsonDecode(row.reportJson), {'participant_count': 15});
      expect(row.responsesJson, isNot(contains('did:')));
    },
  );

  test('rejects an already expired snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(
      () => DeliberationExportCacheService(db).save(
        localBoardId: 'local-board-1',
        title: 'Expired',
        export: {
          'export_id': 'export-old',
          'board_id': 'remote-board-99',
          'deliberation_id': 'deliberation-old',
          'view': 'aggregates',
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
          'manifest': <String, Object?>{},
          'report': <String, Object?>{},
        },
      ),
      throwsA(isA<StateError>()),
    );
  });
}
