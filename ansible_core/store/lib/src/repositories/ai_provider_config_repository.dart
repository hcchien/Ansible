import '../entities/ai_provider_config.dart';

abstract class AiProviderConfigRepository {
  Future<void> save(AiProviderConfig config);
  Future<AiProviderConfig?> getById(String id);
  Future<List<AiProviderConfig>> list();
}
