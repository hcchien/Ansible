import '../entities/local_collection.dart';

abstract class LocalCollectionRepository {
  Future<void> upsert(LocalCollection collection);
  Future<LocalCollection?> getById(String collectionId);
  Future<List<LocalCollection>> list({String? ownerDid});
  Future<void> delete(String collectionId, DateTime updatedAt);
}
