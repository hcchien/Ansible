import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/ai_provider_config.dart' as entity;
import '../ai_provider_config_repository.dart';

class DriftAiProviderConfigRepository implements AiProviderConfigRepository {
  final db.AppDatabase _db;

  DriftAiProviderConfigRepository(this._db);

  @override
  Future<entity.AiProviderConfig?> getById(String id) async {
    final row = await (_db.select(
      _db.aiProviderConfigs,
    )..where((table) => table.providerConfigId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row);
  }

  @override
  Future<List<entity.AiProviderConfig>> list() async {
    final rows = await (_db.select(
      _db.aiProviderConfigs,
    )..orderBy([(table) => OrderingTerm.asc(table.displayName)])).get();
    return rows.map(_mapRow).toList();
  }

  @override
  Future<void> save(entity.AiProviderConfig config) async {
    await _db
        .into(_db.aiProviderConfigs)
        .insert(
          db.AiProviderConfigsCompanion.insert(
            providerConfigId: config.id,
            displayName: config.displayName,
            providerType: config.providerType.name,
            baseUrl: Value(config.baseUrl),
            modelName: Value(config.modelName),
            apiKeyRef: Value(config.apiKeyRef),
            defaultForTransformations: Value(config.defaultForTransformations),
            defaultForSummaries: Value(config.defaultForSummaries),
            createdAt: Value(config.createdAt),
            updatedAt: Value(config.updatedAt),
            isDeleted: Value(config.isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  entity.AiProviderConfig _mapRow(db.AiProviderConfig row) {
    return entity.AiProviderConfig(
      id: row.providerConfigId,
      displayName: row.displayName,
      providerType: entity.AiProviderType.parse(row.providerType),
      baseUrl: row.baseUrl,
      modelName: row.modelName,
      apiKeyRef: row.apiKeyRef,
      defaultForTransformations: row.defaultForTransformations,
      defaultForSummaries: row.defaultForSummaries,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
    );
  }
}
