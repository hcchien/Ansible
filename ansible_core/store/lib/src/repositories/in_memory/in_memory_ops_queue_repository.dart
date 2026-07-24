import 'dart:async';

import '../../entities/ops_queue.dart';
import '../ops_queue_repository.dart';

class InMemoryOpsQueueRepository implements OpsQueueRepository {
  final List<OpsQueueEntry> _entries = [];

  // Broadcast controller — UI widgets subscribe to this.
  // We re-emit the current pending list on every mutation.
  final StreamController<List<OpsQueueEntry>> _pendingController =
      StreamController<List<OpsQueueEntry>>.broadcast();

  // Cached latest subscription starter — simulates BehaviorSubject by
  // wrapping the broadcast stream so new subscribers get the current value.
  List<OpsQueueEntry> _currentPending() =>
      _entries.where((e) => e.status == 'pending').toList();

  List<OpsQueueEntry> _currentOutstanding() => _entries
      .where((e) => e.status == 'pending' || e.status == 'blocked')
      .toList();

  void _notifyPending() {
    if (!_pendingController.isClosed) {
      _pendingController.add(_currentPending());
    }
  }

  @override
  Future<void> enqueue(OpsQueueEntry entry) async {
    _entries.add(entry);
    _notifyPending();
  }

  @override
  Future<List<OpsQueueEntry>> listPending({int limit = 50}) async {
    final pending = _entries.where((e) => e.status == 'pending').toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending.take(limit).toList();
  }

  @override
  Future<List<OpsQueueEntry>> listAll({int limit = 100}) async {
    final all = List<OpsQueueEntry>.from(_entries)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return all.take(limit).toList();
  }

  @override
  Future<void> markSent(String opId) async {
    final idx = _entries.indexWhere((e) => e.opId == opId);
    if (idx == -1) return;
    final existing = _entries[idx];
    _entries[idx] = OpsQueueEntry(
      opId: existing.opId,
      authorDid: existing.authorDid,
      entityType: existing.entityType,
      entityId: existing.entityId,
      opType: existing.opType,
      payload: existing.payload,
      signature: existing.signature,
      status: 'sent',
      createdAt: existing.createdAt,
      sentAt: DateTime.now(),
    );
    _notifyPending();
  }

  @override
  Future<void> markSynced(String opId) async {
    final idx = _entries.indexWhere((e) => e.opId == opId);
    if (idx == -1) return;
    final existing = _entries[idx];
    _entries[idx] = OpsQueueEntry(
      opId: existing.opId,
      authorDid: existing.authorDid,
      entityType: existing.entityType,
      entityId: existing.entityId,
      opType: existing.opType,
      payload: existing.payload,
      signature: existing.signature,
      status: 'synced',
      createdAt: existing.createdAt,
      sentAt: existing.sentAt,
    );
    _notifyPending();
  }

  @override
  Future<void> markRejected(String opId) async {
    final idx = _entries.indexWhere((e) => e.opId == opId);
    if (idx == -1) return;
    final existing = _entries[idx];
    _entries[idx] = OpsQueueEntry(
      opId: existing.opId,
      authorDid: existing.authorDid,
      entityType: existing.entityType,
      entityId: existing.entityId,
      opType: existing.opType,
      payload: existing.payload,
      signature: existing.signature,
      status: 'rejected',
      createdAt: existing.createdAt,
      sentAt: existing.sentAt,
    );
    _notifyPending();
  }

  @override
  Future<void> markBlocked(String opId) => _replaceStatus(opId, 'blocked');

  @override
  Future<int> retryBlocked() async {
    var changed = 0;
    for (var index = 0; index < _entries.length; index++) {
      if (_entries[index].status != 'blocked') continue;
      _entries[index] = _entries[index].copyWith(status: 'pending');
      changed += 1;
    }
    if (changed > 0) _notifyPending();
    return changed;
  }

  Future<void> _replaceStatus(String opId, String status) async {
    final index = _entries.indexWhere((entry) => entry.opId == opId);
    if (index == -1) return;
    _entries[index] = _entries[index].copyWith(status: status);
    _notifyPending();
  }

  @override
  Future<int> pruneSynced({int olderThanDays = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    final before = _entries.length;
    _entries.removeWhere(
      (e) => e.status == 'synced' && e.createdAt.isBefore(cutoff),
    );
    final removed = before - _entries.length;
    if (removed > 0) _notifyPending();
    return removed;
  }

  @override
  Future<int> countPending() async {
    return _entries.where((e) => e.status == 'pending').length;
  }

  @override
  Stream<List<OpsQueueEntry>> watchPending() {
    // Emit current state immediately via an async* wrapper so new subscribers
    // always get a value without waiting for the next mutation.
    final controller = StreamController<List<OpsQueueEntry>>();
    controller.add(_currentPending());
    final sub = _pendingController.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Stream<List<OpsQueueEntry>> watchOutstanding() async* {
    yield _currentOutstanding();
    await for (final _ in _pendingController.stream) {
      yield _currentOutstanding();
    }
  }

  void dispose() {
    _pendingController.close();
  }
}
