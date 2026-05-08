import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/ai_provider_config.dart';
import '../../entities/content_item.dart';
import '../../entities/transformation_job.dart' as entity;
import '../transformation_job_repository.dart';

class DriftTransformationJobRepository implements TransformationJobRepository {
  final db.AppDatabase _db;

  DriftTransformationJobRepository(this._db);

  @override
  Future<void> addSource(entity.TransformationSource source) async {
    await _db
        .into(_db.transformationSources)
        .insert(
          db.TransformationSourcesCompanion.insert(
            transformationJobId: source.transformationJobId,
            contentItemId: source.contentItemId,
            sourceOrder: source.sourceOrder,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> create(entity.TransformationJob job) async {
    await _db
        .into(_db.transformationJobs)
        .insert(
          db.TransformationJobsCompanion.insert(
            transformationJobId: job.id,
            requestedByDid: job.requestedByDid,
            targetMode: job.targetMode.name,
            providerType: job.providerType.name,
            status: job.status.name,
            promptProfile: Value(job.promptProfile),
            inputSnapshotJson: Value(job.inputSnapshotJson),
            outputSnapshotJson: Value(job.outputSnapshotJson),
            errorMessage: Value(job.errorMessage),
            createdAt: Value(job.createdAt),
            updatedAt: Value(job.updatedAt),
            completedAt: Value(job.completedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.TransformationJob?> getById(String id) async {
    final row =
        await (_db.select(_db.transformationJobs)
              ..where((table) => table.transformationJobId.equals(id)))
            .getSingleOrNull();
    if (row == null) return null;
    return _mapJob(row);
  }

  @override
  Future<List<entity.TransformationSource>> listSources(String jobId) async {
    final rows =
        await (_db.select(_db.transformationSources)
              ..where((table) => table.transformationJobId.equals(jobId))
              ..orderBy([(table) => OrderingTerm.asc(table.sourceOrder)]))
            .get();
    return rows
        .map(
          (row) => entity.TransformationSource(
            transformationJobId: row.transformationJobId,
            contentItemId: row.contentItemId,
            sourceOrder: row.sourceOrder,
          ),
        )
        .toList();
  }

  @override
  Future<void> markAccepted(String id, {required DateTime acceptedAt}) async {
    await (_db.update(
      _db.transformationJobs,
    )..where((table) => table.transformationJobId.equals(id))).write(
      db.TransformationJobsCompanion(
        status: Value(entity.TransformationJobStatus.accepted.name),
        updatedAt: Value(acceptedAt),
      ),
    );
  }

  @override
  Future<void> markCompleted(
    String id, {
    required String outputSnapshotJson,
    required DateTime completedAt,
  }) async {
    await (_db.update(
      _db.transformationJobs,
    )..where((table) => table.transformationJobId.equals(id))).write(
      db.TransformationJobsCompanion(
        status: Value(entity.TransformationJobStatus.completed.name),
        outputSnapshotJson: Value(outputSnapshotJson),
        updatedAt: Value(completedAt),
        completedAt: Value(completedAt),
      ),
    );
  }

  entity.TransformationJob _mapJob(db.TransformationJob row) {
    return entity.TransformationJob(
      id: row.transformationJobId,
      requestedByDid: row.requestedByDid,
      targetMode: ContentMode.parse(row.targetMode),
      providerType: AiProviderType.parse(row.providerType),
      status: entity.TransformationJobStatus.parse(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      promptProfile: row.promptProfile,
      inputSnapshotJson: row.inputSnapshotJson,
      outputSnapshotJson: row.outputSnapshotJson,
      errorMessage: row.errorMessage,
      completedAt: row.completedAt,
    );
  }
}
