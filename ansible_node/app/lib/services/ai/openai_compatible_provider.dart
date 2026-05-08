import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';

class OpenAiCompatibleProvider implements AiProvider {
  final Uri baseUrl;
  final String model;
  final String apiKey;
  final http.Client _client;

  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<AiProviderResult> complete(AiProviderRequest request) async {
    final endpoint = _chatCompletionsEndpoint();
    final response = await _client.post(
      endpoint,
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': 'Return JSON only.'},
          {
            'role': 'user',
            'content': jsonEncode({
              'task': request.task,
              'contextPack': request.contextPack,
              'outputSchema': request.outputSchema,
            }),
          },
        ],
        'temperature': 0.2,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(
        'OpenAI-compatible provider returned ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      throw const AiProviderException(
        'Provider response did not include choices',
      );
    }
    final message = choices.first as Map<String, dynamic>;
    final messageBody = message['message'] as Map<String, dynamic>? ?? const {};
    final content = messageBody['content']?.toString() ?? '';
    if (content.trim().isEmpty) {
      throw const AiProviderException('Provider response content was empty');
    }
    final structuredJson = jsonDecode(content) as Map<String, dynamic>;
    return AiProviderResult(
      providerType: 'openaiCompatible',
      structuredJson: structuredJson,
      rawText: content,
    );
  }

  Uri _chatCompletionsEndpoint() {
    final basePath = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$basePath/chat/completions');
  }
}
