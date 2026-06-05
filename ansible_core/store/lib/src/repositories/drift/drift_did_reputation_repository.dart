import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/did_reputation.dart';
import '../did_reputation_repository.dart';

class DriftDidReputationRepository implements DidReputationRepository {
  final AppDatabase _db;

  DriftDidReputationRepository(this._db);

  @override
  Future<void> put(String did, String tier, {DateTime? updatedAt}) async {
    if (did.isEmpty) return;
    await _db
        .into(_db.didReputations)
        .insert(
          DidReputationsCompanion.insert(
            did: did,
            tier: tier,
            updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<String> tierFor(String did) async {
    final row = await (_db.select(
      _db.didReputations,
    )..where((t) => t.did.equals(did))).getSingleOrNull();
    return row?.tier ?? 'basic';
  }

  @override
  Future<Map<String, String>> tiersFor(Iterable<String> dids) async {
    final list = dids.where((d) => d.isNotEmpty).toList();
    if (list.isEmpty) return {};
    final rows = await (_db.select(
      _db.didReputations,
    )..where((t) => t.did.isIn(list))).get();
    return {for (final row in rows) row.did: row.tier};
  }

  @override
  Future<List<DidReputation>> list() async {
    final rows = await _db.select(_db.didReputations).get();
    return rows
        .map(
          (r) =>
              DidReputation(did: r.did, tier: r.tier, updatedAt: r.updatedAt),
        )
        .toList();
  }
}
