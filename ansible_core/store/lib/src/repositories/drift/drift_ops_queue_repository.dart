import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/ops_queue.dart' as entity;
import '../ops_queue_repository.dart';

class DriftOpsQueueRepository implements OpsQueueRepository {
  final AppDatabase _db;

  DriftOpsQueueRepository(this._db);

  // ------------------------------------------------------------------ enqueue

  @override
  Future<void> enqueue(entity.OpsQueueEntry entry) async {
    await _db
        .into(_db.opsQueue)
        .insertOnConflictUpdate(
          OpsQueueCompanion.insert(
            opId: entry.opId,
            authorDid: entry.authorDid,
            entityType: entry.entityType,
            entityId: entry.entityId,
            opType: entry.opType,
            payload: entry.payload,
            signature: entry.signature,
            status: Value(entry.status),
            createdAt: Value(entry.createdAt),
            sentAt: Value(entry.sentAt),
          ),
        );
  }

  // --------------------------------------------------------------- listPending

  @override
  Future<List<entity.OpsQueueEntry>> listPending({int limit = 50}) async {
    final rows =
        await ((_db.select(_db.opsQueue)
              ..where((t) => t.status.equals('pending'))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(limit)))
            .get();
    return rows.map(_mapRow).toList();
  }

  // ----------------------------------------------------------------- listAll

  @override
  Future<List<entity.OpsQueueEntry>> listAll({int limit = 100}) async {
    final rows =
        await ((_db.select(_db.opsQueue)
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(limit)))
            .get();
    return rows.map(_mapRow).toList();
  }

  // ---------------------------------------------------------------- markSent

  @override
  Future<void> markSent(String opId) async {
    await (_db.update(_db.opsQueue)..where((t) => t.opId.equals(opId))).write(
      OpsQueueCompanion(
        status: const Value('sent'),
        sentAt: Value(DateTime.now()),
      ),
    );
  }

  // --------------------------------------------------------------- markSynced

  @override
  Future<void> markSynced(String opId) async {
    await (_db.update(_db.opsQueue)..where((t) => t.opId.equals(opId))).write(
      const OpsQueueCompanion(status: Value('synced')),
    );
  }

  // ------------------------------------------------------------- markRejected

  @override
  Future<void> markRejected(String opId) async {
    await (_db.update(_db.opsQueue)..where((t) => t.opId.equals(opId))).write(
      const OpsQueueCompanion(status: Value('rejected')),
    );
  }

  @override
  Future<void> markBlocked(String opId) async {
    await (_db.update(_db.opsQueue)..where((t) => t.opId.equals(opId))).write(
      const OpsQueueCompanion(status: Value('blocked')),
    );
  }

  @override
  Future<int> retryBlocked() {
    return (_db.update(_db.opsQueue)..where((t) => t.status.equals('blocked')))
        .write(const OpsQueueCompanion(status: Value('pending')));
  }

  // ------------------------------------------------------------- pruneSynced

  @override
  Future<int> pruneSynced({int olderThanDays = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    final count =
        await (_db.delete(_db.opsQueue)..where(
              (t) =>
                  t.status.equals('synced') &
                  t.createdAt.isSmallerThanValue(cutoff),
            ))
            .go();
    return count;
  }

  // ------------------------------------------------------------ countPending

  @override
  Future<int> countPending() async {
    final count = await _db.opsQueue
        .count(where: (t) => t.status.equals('pending'))
        .getSingle();
    return count;
  }

  // ------------------------------------------------------------ watchPending

  @override
  Stream<List<entity.OpsQueueEntry>> watchPending() {
    return (_db.select(_db.opsQueue)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Stream<List<entity.OpsQueueEntry>> watchOutstanding() {
    final query = _db.select(_db.opsQueue)
      ..where(
        (table) =>
            table.status.equals('pending') | table.status.equals('blocked'),
      )
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_mapRow).toList(growable: false),
    );
  }

  // ---------------------------------------------------------------- helpers

  entity.OpsQueueEntry _mapRow(OpsQueueData row) {
    return entity.OpsQueueEntry(
      opId: row.opId,
      authorDid: row.authorDid,
      entityType: row.entityType,
      entityId: row.entityId,
      opType: row.opType,
      payload: row.payload,
      signature: row.signature,
      status: row.status,
      createdAt: row.createdAt,
      sentAt: row.sentAt,
    );
  }
}
