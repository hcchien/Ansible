import '../entities/content_item.dart';

abstract class ContentItemRepository {
  Future<ContentItem?> getById(String id);
  Future<List<ContentItem>> list({ContentMode? mode, String? authorDid});
  Future<void> create(ContentItem item);
  Future<void> update(ContentItem item);
  Future<void> delete(String id);
}
