import '../entities/ops_queue.dart';

abstract class OpsQueueRepository {
  /// Add a new op to the local queue with status 'pending'.
  Future<void> enqueue(OpsQueueEntry entry);

  /// List pending ops (oldest first), up to [limit].
  Future<List<OpsQueueEntry>> listPending({int limit = 50});

  /// List all ops regardless of status.
  Future<List<OpsQueueEntry>> listAll({int limit = 100});

  /// Mark an op as 'sent' (first transmission attempt).
  Future<void> markSent(String opId);

  /// Mark an op as 'synced' (relay acknowledged).
  Future<void> markSynced(String opId);

  /// Mark an op as 'rejected' (relay refused).
  Future<void> markRejected(String opId);

  /// Mark an op as blocked by a recoverable board policy/capability decision.
  Future<void> markBlocked(String opId);

  /// Move recoverably blocked ops back to pending for an explicit sync retry.
  Future<int> retryBlocked();

  /// Delete ops with status 'synced' older than [olderThanDays].
  Future<int> pruneSynced({int olderThanDays = 7});

  /// Count pending ops.
  Future<int> countPending();

  /// Reactive stream of pending ops (for UI badges).
  Stream<List<OpsQueueEntry>> watchPending();

  /// Reactive stream of pending and policy-blocked ops.
  Stream<List<OpsQueueEntry>> watchOutstanding();
}
