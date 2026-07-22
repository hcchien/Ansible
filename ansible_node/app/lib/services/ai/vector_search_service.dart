import 'dart:math';
import 'package:ansible_store/ansible_store.dart';
import 'embedding_service.dart';

class MurmurSearchResult {
  final ContentItem murmur;
  final double score;
  const MurmurSearchResult({required this.murmur, required this.score});
}

class VectorSearchService {
  final EmbeddingService _embedding;
  final DriftMurmurEmbeddingRepository _embeddingRepo;
  final DriftContentItemRepository _contentItems;

  const VectorSearchService({
    required EmbeddingService embeddingService,
    required DriftMurmurEmbeddingRepository embeddingRepository,
    required DriftContentItemRepository contentItemRepository,
  }) : _embedding = embeddingService,
       _embeddingRepo = embeddingRepository,
       _contentItems = contentItemRepository;

  Future<List<MurmurSearchResult>> search({
    required String query,
    int topK = 20,
    DateTime? since, // null = all time
  }) async {
    if (query.trim().isEmpty) return [];

    // 1. Embed the query locally
    final queryVec = await _embedding.embed(query);

    // 2. Load stored vectors (filtered by date if chip selected)
    final stored = await _embeddingRepo.getAll(since: since);
    if (stored.isEmpty) return [];

    // 3. Cosine similarity ranking (pure Dart, no API)
    final scored = <({String id, double score})>[];
    for (final entry in stored) {
      final score = _cosine(queryVec, entry.vector);
      if (score > 0.3) scored.add((id: entry.contentItemId, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final topIds = scored.take(topK).map((e) => e.id).toList();

    if (topIds.isEmpty) return [];

    // 4. Fetch ContentItems for matched IDs
    final murmurs = await Future.wait(
      topIds.map((id) => _contentItems.getById(id)),
    );

    return [
      for (int i = 0; i < topIds.length; i++)
        if (murmurs[i] != null)
          MurmurSearchResult(murmur: murmurs[i]!, score: scored[i].score),
    ];
  }

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
