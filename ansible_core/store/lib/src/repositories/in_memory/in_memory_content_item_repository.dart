import '../../entities/content_item.dart';
import '../content_item_repository.dart';

class InMemoryContentItemRepository implements ContentItemRepository {
  final Map<String, ContentItem> _items = {};

  @override
  Future<void> create(ContentItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> delete(String id) async {
    final item = _items[id];
    if (item == null) return;
    _items[id] = ContentItem(
      id: item.id,
      authorDid: item.authorDid,
      mode: item.mode,
      body: item.body,
      status: item.status,
      visibility: item.visibility,
      createdAt: item.createdAt,
      updatedAt: DateTime.now().toUtc(),
      subjectId: item.subjectId,
      title: item.title,
      publishedAt: item.publishedAt,
      isDeleted: true,
      localOnly: item.localOnly,
    );
  }

  @override
  Future<ContentItem?> getById(String id) async {
    return _items[id];
  }

  @override
  Future<List<ContentItem>> list({ContentMode? mode, String? authorDid}) async {
    final items = _items.values.where((item) {
      if (mode != null && item.mode != mode) return false;
      if (authorDid != null && item.authorDid != authorDid) return false;
      return true;
    }).toList()..sort(_compareContentItems);
    return items;
  }

  @override
  Future<void> update(ContentItem item) async {
    _items[item.id] = item;
  }

  int _compareContentItems(ContentItem a, ContentItem b) {
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  }
}
