/// Abstract interface for on-device text embedding.
/// Implementations include [AppleNLEmbeddingService] (iOS NaturalLanguage)
/// and future ONNX-based variants.
abstract class EmbeddingService {
  /// Returns a unit-normalised embedding vector for [text].
  Future<List<double>> embed(String text);

  /// Dimensionality of the embedding vectors produced by this service.
  int get dimension;

  /// Identifier for the underlying model.
  /// Used to detect when stored embeddings need re-indexing.
  String get modelVersion;
}
