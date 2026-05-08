import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

typedef AiConfigClock = DateTime Function();
typedef AiConfigIdFactory = String Function();

class AiProviderConfigStore {
  final AiProviderConfigRepository _repository;
  final FlutterSecureStorage _secureStorage;
  final AiConfigClock _clock;
  final AiConfigIdFactory _idFactory;

  AiProviderConfigStore({
    required AiProviderConfigRepository repository,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    AiConfigClock? clock,
    AiConfigIdFactory? idFactory,
  }) : _repository = repository,
       _secureStorage = secureStorage,
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? const Uuid().v4;

  Future<AiProviderConfig> save({
    required String displayName,
    required AiProviderType providerType,
    String? baseUrl,
    String? modelName,
    String? apiKey,
    bool defaultForTransformations = false,
    bool defaultForSummaries = false,
  }) async {
    final id = _idFactory();
    final apiKeyRef = apiKey == null || apiKey.isEmpty
        ? null
        : 'ai_provider:$id:api_key';
    if (apiKeyRef != null) {
      await _secureStorage.write(key: apiKeyRef, value: apiKey);
    }
    final now = _clock().toUtc();
    final config = AiProviderConfig(
      id: id,
      displayName: displayName,
      providerType: providerType,
      baseUrl: baseUrl,
      modelName: modelName,
      apiKeyRef: apiKeyRef,
      defaultForTransformations: defaultForTransformations,
      defaultForSummaries: defaultForSummaries,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.save(config);
    return config;
  }

  Future<String?> readApiKey(AiProviderConfig config) async {
    final ref = config.apiKeyRef;
    if (ref == null) return null;
    return _secureStorage.read(key: ref);
  }
}
