import '../../entities/thread.dart';
import '../thread_repository.dart';

class InMemoryThreadRepository implements ThreadRepository {
  final Map<String, Thread> _threads = {};

  @override
  Future<void> create(Thread thread) async {
    _threads[thread.id] = thread;
  }

  @override
  Future<Thread?> getById(String id) async {
    return _threads[id];
  }

  @override
  Future<List<Thread>> list({String? boardId}) async {
    if (boardId != null) {
      return _threads.values.where((t) => t.boardId == boardId).toList();
    }
    return _threads.values.toList();
  }

  @override
  Future<void> update(Thread thread) async {
    if (_threads.containsKey(thread.id)) {
      _threads[thread.id] = thread;
    }
  }
  @override
  Future<void> delete(String id) async {
    _threads.remove(id);
  }
}
