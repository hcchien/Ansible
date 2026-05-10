import '../../entities/local_collection.dart';
import '../local_collection_repository.dart';

class InMemoryLocalCollectionRepository implements LocalCollectionRepository {
  final Map<String, LocalCollection> _collections = {};

  @override
  Future<void> upsert(LocalCollection collection) async {
    _collections[collection.collectionId] = collection;
  }

  @override
  Future<LocalCollection?> getById(String collectionId) async {
    return _collections[collectionId];
  }

  @override
  Future<List<LocalCollection>> list({String? ownerDid}) async {
    final collections = _collections.values.where((collection) {
      return ownerDid == null || collection.ownerDid == ownerDid;
    }).toList()..sort((a, b) => a.title.compareTo(b.title));
    return collections;
  }

  @override
  Future<void> delete(String collectionId, DateTime updatedAt) async {
    final collection = _collections[collectionId];
    if (collection == null) return;
    _collections[collectionId] = collection.copyWith(
      isDeleted: true,
      updatedAt: updatedAt,
    );
  }
}
