import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/context_pack.dart' as entity;
import '../context_pack_repository.dart';

class DriftContextPackRepository implements ContextPackRepository {
  final db.AppDatabase _db;

  DriftContextPackRepository(this._db);

  @override
  Future<void> create(entity.ContextPack contextPack) async {
    await _db
        .into(_db.contextPacks)
        .insert(
          db.ContextPacksCompanion.insert(
            contextPackId: contextPack.id,
            purpose: contextPack.purpose.name,
            sourceRefsJson: contextPack.sourceRefsJson,
            snapshotJson: contextPack.snapshotJson,
            privacyLevel: contextPack.privacyLevel.name,
            allowedRemote: Value(contextPack.allowedRemote),
            createdByDid: contextPack.createdByDid,
            createdAt: Value(contextPack.createdAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.ContextPack?> getById(String id) async {
    final row = await (_db.select(
      _db.contextPacks,
    )..where((table) => table.contextPackId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return entity.ContextPack(
      id: row.contextPackId,
      purpose: entity.ContextPackPurpose.parse(row.purpose),
      sourceRefsJson: row.sourceRefsJson,
      snapshotJson: row.snapshotJson,
      privacyLevel: entity.ContextPrivacyLevel.parse(row.privacyLevel),
      allowedRemote: row.allowedRemote,
      createdByDid: row.createdByDid,
      createdAt: row.createdAt,
    );
  }
}
