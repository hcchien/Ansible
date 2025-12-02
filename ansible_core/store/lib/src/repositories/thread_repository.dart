import '../entities/thread.dart';

abstract class ThreadRepository {
  Future<Thread?> getById(String id);
  Future<List<Thread>> list({String? boardId});
  Future<void> create(Thread thread);
  Future<void> update(Thread thread);
  Future<void> delete(String id);
}
