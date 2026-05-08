class AiProviderRequest {
  final String task;
  final Map<String, dynamic> contextPack;
  final Map<String, dynamic> outputSchema;

  const AiProviderRequest({
    required this.task,
    required this.contextPack,
    required this.outputSchema,
  });
}

class AiProviderResult {
  final String providerType;
  final Map<String, dynamic> structuredJson;
  final String rawText;

  const AiProviderResult({
    required this.providerType,
    required this.structuredJson,
    required this.rawText,
  });
}

abstract class AiProvider {
  Future<AiProviderResult> complete(AiProviderRequest request);
}

class AiProviderException implements Exception {
  final String message;

  const AiProviderException(this.message);

  @override
  String toString() => 'AiProviderException: $message';
}
