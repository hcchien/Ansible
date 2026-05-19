import 'package:ansible_store/ansible_store.dart';
import 'embedding_service.dart';

class MurmurIndexingService {
  final EmbeddingService _embedding;
  final DriftMurmurEmbeddingRepository _embeddingRepo;
  final DriftContentItemRepository _contentItems;

  const MurmurIndexingService({
    required EmbeddingService embeddingService,
    required DriftMurmurEmbeddingRepository embeddingRepository,
    required DriftContentItemRepository contentItemRepository,
  })  : _embedding = embeddingService,
        _embeddingRepo = embeddingRepository,
        _contentItems = contentItemRepository;

  /// Index a single murmur immediately after it is saved.
  Future<void> index(ContentItem item) async {
    if (item.mode != ContentMode.murmur) return;
    final text = item.body.trim();
    if (text.isEmpty) return;
    final vector = await _embedding.embed(text);
    await _embeddingRepo.upsert(
      contentItemId: item.id,
      modelVersion: _embedding.modelVersion,
      vector: vector,
    );
  }

  /// Called once at app start — indexes any murmur that has no embedding yet.
  /// Runs entries one at a time to avoid overwhelming the MethodChannel.
  Future<void> indexAllPending() async {
    final allMurmurs = await _contentItems.list(mode: ContentMode.murmur);
    final indexed = await _embeddingRepo.allIndexedIds();
    final pending = allMurmurs.where((m) => !indexed.contains(m.id)).toList();
    for (final m in pending) {
      await index(m);
    }
  }
}
