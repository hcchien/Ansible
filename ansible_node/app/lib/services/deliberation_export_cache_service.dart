import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/drift.dart';

/// Persists only Forum Host exports the user explicitly chose to expose to
/// Local AI. Expiry remains part of the row so the MCP can fail closed even if
/// an old snapshot has not yet been cleaned up by the app.
class DeliberationExportCacheService {
  const DeliberationExportCacheService(this.db);

  final AppDatabase db;

  Future<void> save({
    required String localBoardId,
    required String title,
    required Map<String, dynamic> export,
  }) async {
    final exportId = _requiredString(export, 'export_id');
    _requiredString(export, 'board_id');
    final deliberationId = _requiredString(export, 'deliberation_id');
    final view = _requiredString(export, 'view');
    final expiresAt = DateTime.parse(
      _requiredString(export, 'expires_at'),
    ).toUtc();
    if (!expiresAt.isAfter(DateTime.now().toUtc())) {
      throw StateError('deliberation_export_expired');
    }

    final manifest = export['manifest'];
    final report = export['report'];
    if (manifest is! Map || report is! Map) {
      throw const FormatException('Invalid deliberation export payload');
    }

    await db
        .into(db.deliberationExports)
        .insert(
          DeliberationExportsCompanion.insert(
            exportId: exportId,
            boardId: localBoardId,
            deliberationId: deliberationId,
            title: title,
            view: view,
            manifestJson: jsonEncode(manifest),
            reportJson: jsonEncode(report),
            statementsJson: Value(
              export['statements'] == null
                  ? null
                  : jsonEncode(export['statements']),
            ),
            responsesJson: Value(
              export['responses'] == null
                  ? null
                  : jsonEncode(export['responses']),
            ),
            expiresAt: expiresAt,
          ),
          mode: InsertMode.insertOrReplace,
        );

    await (db.delete(db.deliberationExports)..where(
          (row) => row.expiresAt.isSmallerOrEqualValue(DateTime.now().toUtc()),
        ))
        .go();
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final result = value[key]?.toString().trim() ?? '';
    if (result.isEmpty) throw FormatException('Missing $key');
    return result;
  }
}
