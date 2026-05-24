import 'package:ansible_store/ansible_store.dart';
import 'ai_privacy_policy.dart';
import 'ai_provider.dart';

class MurmurSynthesisService {
  final AiProvider _provider;
  final AiProviderType providerType;
  final bool explicitRemoteConsent;

  const MurmurSynthesisService(
    this._provider, {
    this.providerType = AiProviderType.manual,
    this.explicitRemoteConsent = false,
  });

  Future<String> synthesize({
    required List<ContentItem> selectedMurmurs,
    String? noteTitle,
    String? noteBodyExcerpt,
  }) async {
    if (selectedMurmurs.isEmpty) {
      throw const MurmurSynthesisException('No murmurs selected for synthesis');
    }
    final privacyLevel = _privacyLevel(
      selectedMurmurs: selectedMurmurs,
      noteTitle: noteTitle,
      noteBodyExcerpt: noteBodyExcerpt,
    );
    final privacyDecision = AiPrivacyPolicy.evaluate(
      providerType: providerType,
      privacyLevel: privacyLevel,
      explicitRemoteConsent: explicitRemoteConsent,
    );
    if (!privacyDecision.allowed) {
      throw AiProviderException(
        privacyDecision.reason ?? 'Remote provider request is not allowed.',
      );
    }

    final bodyExcerpt = noteBodyExcerpt != null && noteBodyExcerpt.length > 400
        ? '${noteBodyExcerpt.substring(0, 400)}…'
        : (noteBodyExcerpt ?? '');

    final request = AiProviderRequest(
      task: 'synthesize_for_note',
      contextPack: {
        'note_context': {'title': noteTitle ?? '', 'body_excerpt': bodyExcerpt},
        'selected_murmurs': selectedMurmurs
            .map((m) => {'body': m.body})
            .toList(),
      },
      outputSchema: {
        'draft_paragraph':
            'string — a paragraph that synthesises the selected murmurs, '
            'written in the same voice, to be appended to the note',
      },
    );

    final result = await _provider.complete(request);
    final json = result.structuredJson;
    final draft = json['draft_paragraph']?.toString();
    if (draft == null || draft.trim().isEmpty) {
      throw const MurmurSynthesisException(
        'AI did not return a draft paragraph',
      );
    }
    return draft.trim();
  }

  ContextPrivacyLevel _privacyLevel({
    required List<ContentItem> selectedMurmurs,
    String? noteTitle,
    String? noteBodyExcerpt,
  }) {
    if (noteTitle != null && noteTitle.trim().isNotEmpty) {
      return ContextPrivacyLevel.containsPrivate;
    }
    if (noteBodyExcerpt != null && noteBodyExcerpt.trim().isNotEmpty) {
      return ContextPrivacyLevel.containsPrivate;
    }
    for (final item in selectedMurmurs) {
      if (item.localOnly || item.visibility == ContentVisibility.private) {
        return ContextPrivacyLevel.containsPrivate;
      }
    }
    return ContextPrivacyLevel.publicOnly;
  }
}

class MurmurSynthesisException implements Exception {
  final String message;
  const MurmurSynthesisException(this.message);
  @override
  String toString() => 'MurmurSynthesisException: $message';
}
