import 'package:ansible_node/services/ai/ai_provider_config_store.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiProviderConfigStore', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test(
      'stores API key in secure storage and metadata in repository',
      () async {
        final repository = InMemoryAiProviderConfigRepository();
        final store = AiProviderConfigStore(
          repository: repository,
          secureStorage: const FlutterSecureStorage(),
          clock: () => DateTime.utc(2026, 5, 8, 12),
        );

        final config = await store.save(
          displayName: 'OpenAI compatible',
          providerType: AiProviderType.openaiCompatible,
          baseUrl: 'https://llm.example/v1',
          modelName: 'test-model',
          apiKey: 'secret-key',
        );

        final loaded = await repository.getById(config.id);
        expect(loaded, isNotNull);
        expect(loaded!.apiKeyRef, 'ai_provider:${config.id}:api_key');
        expect(loaded.apiKeyRef, isNot('secret-key'));
        expect(await store.readApiKey(config), 'secret-key');
      },
    );
  });
}
