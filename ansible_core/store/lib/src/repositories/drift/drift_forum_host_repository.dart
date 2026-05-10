import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/forum_host.dart' as entity;
import '../forum_host_repository.dart';

class DriftForumHostRepository implements ForumHostRepository {
  DriftForumHostRepository(this._db);

  final db.AppDatabase _db;

  @override
  Future<entity.ForumHost?> getById(String forumHostId) async {
    final row =
        await (_db.select(_db.forumHosts)
              ..where((table) => table.forumHostId.equals(forumHostId)))
            .getSingleOrNull();
    return row == null ? null : _mapHost(row);
  }

  @override
  Future<List<entity.ForumHost>> list({bool includeInactive = true}) async {
    final query = _db.select(_db.forumHosts)
      ..orderBy([(table) => OrderingTerm.asc(table.displayName)]);
    if (!includeInactive) {
      query.where((table) => table.isActive.equals(true));
    }
    final rows = await query.get();
    return rows.map(_mapHost).toList();
  }

  @override
  Future<List<entity.ForumHost>> listActive() {
    return list(includeInactive: false);
  }

  @override
  Future<void> upsert(entity.ForumHost host) async {
    await _db
        .into(_db.forumHosts)
        .insertOnConflictUpdate(
          db.ForumHostsCompanion.insert(
            forumHostId: host.forumHostId,
            displayName: host.displayName,
            baseUrl: host.baseUrl,
            canonicalHostUri: host.canonicalHostUri,
            serverKind: host.serverKind,
            capabilitiesJson: Value(jsonEncode(host.capabilities)),
            isActive: Value(host.isActive),
            createdAt: Value(host.createdAt),
            updatedAt: Value(host.updatedAt),
          ),
        );
  }

  entity.ForumHost _mapHost(db.ForumHost row) {
    return entity.ForumHost(
      forumHostId: row.forumHostId,
      displayName: row.displayName,
      baseUrl: row.baseUrl,
      canonicalHostUri: row.canonicalHostUri,
      serverKind: row.serverKind,
      capabilities: _decodeObjectMap(row.capabilitiesJson),
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Map<String, Object?> _decodeObjectMap(String json) {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }
}
