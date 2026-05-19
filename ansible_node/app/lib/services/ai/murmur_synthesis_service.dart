import 'package:ansible_store/ansible_store.dart';
import 'ai_provider.dart';

class MurmurSynthesisService {
  final AiProvider _provider;
  const MurmurSynthesisService(this._provider);

  Future<String> synthesize({
    required List<ContentItem> selectedMurmurs,
    String? noteTitle,
    String? noteBodyExcerpt,
  }) async {
    if (selectedMurmurs.isEmpty) {
      throw const MurmurSynthesisException('No murmurs selected for synthesis');
    }
    final bodyExcerpt = noteBodyExcerpt != null && noteBodyExcerpt.length > 400
        ? '${noteBodyExcerpt.substring(0, 400)}…'
        : (noteBodyExcerpt ?? '');

    final request = AiProviderRequest(
      task: 'synthesize_for_note',
      contextPack: {
        'note_context': {
          'title': noteTitle ?? '',
          'body_excerpt': bodyExcerpt,
        },
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
}

class MurmurSynthesisException implements Exception {
  final String message;
  const MurmurSynthesisException(this.message);
  @override
  String toString() => 'MurmurSynthesisException: $message';
}
