import 'package:ansible_node/services/ai/ai_privacy_policy.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI privacy policy', () {
    test('allows public-only context for remote providers', () {
      final decision = AiPrivacyPolicy.evaluate(
        providerType: AiProviderType.openaiCompatible,
        privacyLevel: ContextPrivacyLevel.publicOnly,
      );

      expect(decision.allowed, isTrue);
      expect(decision.requiresExplicitConsent, isFalse);
    });

    test('blocks private remote context without one-request consent', () {
      final decision = AiPrivacyPolicy.evaluate(
        providerType: AiProviderType.openaiCompatible,
        privacyLevel: ContextPrivacyLevel.containsPrivate,
      );

      expect(decision.allowed, isFalse);
      expect(decision.requiresExplicitConsent, isTrue);
      expect(decision.reason, contains('private'));
    });

    test('allows private remote context with explicit one-request consent', () {
      final decision = AiPrivacyPolicy.evaluate(
        providerType: AiProviderType.openaiCompatible,
        privacyLevel: ContextPrivacyLevel.containsPrivate,
        explicitRemoteConsent: true,
      );

      expect(decision.allowed, isTrue);
      expect(decision.requiresExplicitConsent, isTrue);
    });

    test('allows private context for manual and local providers', () {
      for (final providerType in [
        AiProviderType.manual,
        AiProviderType.localHttp,
      ]) {
        final decision = AiPrivacyPolicy.evaluate(
          providerType: providerType,
          privacyLevel: ContextPrivacyLevel.containsPrivate,
        );

        expect(decision.allowed, isTrue);
      }
    });
  });
}
