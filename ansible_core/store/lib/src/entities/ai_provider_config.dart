enum AiProviderType {
  manual,
  openaiCompatible,
  localHttp,
  system;

  static AiProviderType parse(String value) {
    return AiProviderType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown AiProviderType "$value"'),
    );
  }
}

class AiProviderConfig {
  final String id;
  final String displayName;
  final AiProviderType providerType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? baseUrl;
  final String? modelName;
  final String? apiKeyRef;
  final bool defaultForTransformations;
  final bool defaultForSummaries;
  final bool isDeleted;

  const AiProviderConfig({
    required this.id,
    required this.displayName,
    required this.providerType,
    required this.createdAt,
    required this.updatedAt,
    this.baseUrl,
    this.modelName,
    this.apiKeyRef,
    this.defaultForTransformations = false,
    this.defaultForSummaries = false,
    this.isDeleted = false,
  });
}
