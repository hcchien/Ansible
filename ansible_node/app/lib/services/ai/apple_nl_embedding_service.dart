import 'package:flutter/services.dart';
import 'embedding_service.dart';

/// Embedding service backed by Apple's NaturalLanguage framework.
/// Requires iOS 14.0+.
/// Uses NLEmbedding.sentenceEmbedding(for: .traditionalChinese).
class AppleNLEmbeddingService implements EmbeddingService {
  static const _channel = MethodChannel('ansible_node/embedding');

  const AppleNLEmbeddingService();

  @override
  Future<List<double>> embed(String text) async {
    final result = await _channel.invokeMethod<List<dynamic>>('embed', {
      'text': text,
    });
    if (result == null) {
      throw EmbeddingException('Embedding service returned null for: $text');
    }
    return result.map((v) => (v as num).toDouble()).toList();
  }

  @override
  int get dimension => 512;

  @override
  String get modelVersion => 'apple-nl-tc-v1';
}

class EmbeddingException implements Exception {
  final String message;
  const EmbeddingException(this.message);
  @override
  String toString() => 'EmbeddingException: $message';
}
