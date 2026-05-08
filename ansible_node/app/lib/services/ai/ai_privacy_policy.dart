import 'package:ansible_store/ansible_store.dart';

class AiPrivacyDecision {
  final bool allowed;
  final bool requiresExplicitConsent;
  final String? reason;

  const AiPrivacyDecision({
    required this.allowed,
    required this.requiresExplicitConsent,
    this.reason,
  });
}

class AiPrivacyPolicy {
  static AiPrivacyDecision evaluate({
    required AiProviderType providerType,
    required ContextPrivacyLevel privacyLevel,
    bool explicitRemoteConsent = false,
  }) {
    final isRemote =
        providerType == AiProviderType.openaiCompatible ||
        providerType == AiProviderType.system;
    final containsNonPublic =
        privacyLevel == ContextPrivacyLevel.containsPrivate ||
        privacyLevel == ContextPrivacyLevel.containsSensitive;

    if (!isRemote || !containsNonPublic) {
      return const AiPrivacyDecision(
        allowed: true,
        requiresExplicitConsent: false,
      );
    }
    if (explicitRemoteConsent) {
      return const AiPrivacyDecision(
        allowed: true,
        requiresExplicitConsent: true,
      );
    }
    final label = privacyLevel == ContextPrivacyLevel.containsSensitive
        ? 'sensitive'
        : 'private';
    return AiPrivacyDecision(
      allowed: false,
      requiresExplicitConsent: true,
      reason: 'Remote provider request includes $label content.',
    );
  }
}
