import 'ai_provider.dart';

class ManualAiProvider implements AiProvider {
  @override
  Future<AiProviderResult> complete(AiProviderRequest request) async {
    final sourceText = _extractSourceText(request.contextPack);
    if (request.task.endsWith('_summary')) {
      final summary = sourceText.isEmpty
          ? 'Manual summary placeholder. Edit this before saving.'
          : sourceText;
      final structuredJson = <String, dynamic>{'summary': summary};
      return AiProviderResult(
        providerType: 'manual',
        structuredJson: structuredJson,
        rawText: structuredJson.toString(),
      );
    }
    final title = 'Manual ${request.task.replaceAll('_', ' ')} draft';
    final body = sourceText.isEmpty
        ? 'Manual draft placeholder. Edit this before accepting.'
        : sourceText;
    final structuredJson = <String, dynamic>{'title': title, 'body': body};
    return AiProviderResult(
      providerType: 'manual',
      structuredJson: structuredJson,
      rawText: structuredJson.toString(),
    );
  }

  String _extractSourceText(Map<String, dynamic> contextPack) {
    final sources = contextPack['sources'];
    if (sources is List) {
      return sources
          .map((source) {
            if (source is Map && source['body'] != null) {
              return source['body'].toString();
            }
            return source.toString();
          })
          .where((text) => text.trim().isNotEmpty)
          .join('\n\n');
    }
    return '';
  }
}
