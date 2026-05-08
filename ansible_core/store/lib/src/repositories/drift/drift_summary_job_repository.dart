import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/summary_job.dart' as entity;
import '../summary_job_repository.dart';

class DriftSummaryJobRepository implements SummaryJobRepository {
  final db.AppDatabase _db;

  DriftSummaryJobRepository(this._db);

  @override
  Future<void> create(entity.SummaryJob job) async {
    await _db
        .into(_db.summaryJobs)
        .insert(
          db.SummaryJobsCompanion.insert(
            summaryJobId: job.id,
            requestedByDid: job.requestedByDid,
            contextPackId: job.contextPackId,
            providerConfigId: job.providerConfigId,
            summaryType: job.summaryType,
            status: job.status.name,
            resultJson: Value(job.resultJson),
            errorMessage: Value(job.errorMessage),
            createdAt: Value(job.createdAt),
            updatedAt: Value(job.updatedAt),
            completedAt: Value(job.completedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.SummaryJob?> getById(String id) async {
    final row = await (_db.select(
      _db.summaryJobs,
    )..where((table) => table.summaryJobId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row);
  }

  @override
  Future<void> markCompleted(
    String id, {
    required String resultJson,
    required DateTime completedAt,
  }) async {
    await (_db.update(
      _db.summaryJobs,
    )..where((table) => table.summaryJobId.equals(id))).write(
      db.SummaryJobsCompanion(
        status: Value(entity.SummaryJobStatus.completed.name),
        resultJson: Value(resultJson),
        updatedAt: Value(completedAt),
        completedAt: Value(completedAt),
      ),
    );
  }

  entity.SummaryJob _mapRow(db.SummaryJob row) {
    return entity.SummaryJob(
      id: row.summaryJobId,
      requestedByDid: row.requestedByDid,
      contextPackId: row.contextPackId,
      providerConfigId: row.providerConfigId,
      summaryType: row.summaryType,
      status: entity.SummaryJobStatus.parse(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      resultJson: row.resultJson,
      errorMessage: row.errorMessage,
      completedAt: row.completedAt,
    );
  }
}
