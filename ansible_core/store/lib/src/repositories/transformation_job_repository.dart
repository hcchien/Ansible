import '../entities/transformation_job.dart';

abstract class TransformationJobRepository {
  Future<void> create(TransformationJob job);
  Future<TransformationJob?> getById(String id);
  Future<void> addSource(TransformationSource source);
  Future<List<TransformationSource>> listSources(String jobId);
  Future<void> markCompleted(
    String id, {
    required String outputSnapshotJson,
    required DateTime completedAt,
  });
  Future<void> markAccepted(String id, {required DateTime acceptedAt});
}
