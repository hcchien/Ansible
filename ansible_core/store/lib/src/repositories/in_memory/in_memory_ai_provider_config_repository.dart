import '../../entities/ai_provider_config.dart';
import '../ai_provider_config_repository.dart';

class InMemoryAiProviderConfigRepository implements AiProviderConfigRepository {
  final Map<String, AiProviderConfig> _configs = {};

  @override
  Future<AiProviderConfig?> getById(String id) async {
    return _configs[id];
  }

  @override
  Future<List<AiProviderConfig>> list() async {
    return _configs.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Future<void> save(AiProviderConfig config) async {
    _configs[config.id] = config;
  }
}
