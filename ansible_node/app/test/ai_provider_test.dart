import 'dart:convert';

import 'package:ansible_node/services/ai/ai_provider.dart';
import 'package:ansible_node/services/ai/local_http_provider.dart';
import 'package:ansible_node/services/ai/manual_ai_provider.dart';
import 'package:ansible_node/services/ai/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AI providers', () {
    test('manual provider returns deterministic draft output', () async {
      final provider = ManualAiProvider();

      final result = await provider.complete(
        const AiProviderRequest(
          task: 'murmur_to_note',
          contextPack: {
            'sources': [
              {'body': 'Raw thought'},
            ],
          },
          outputSchema: {'type': 'object'},
        ),
      );

      expect(result.providerType, 'manual');
      expect(result.structuredJson['title'], 'Manual murmur to note draft');
      expect(result.structuredJson['body'], contains('Raw thought'));
    });

    test('OpenAI-compatible provider sends messages and parses JSON', () async {
      final provider = OpenAiCompatibleProvider(
        baseUrl: Uri.parse('https://llm.example/v1'),
        model: 'test-model',
        apiKey: 'secret-key',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://llm.example/v1/chat/completions',
          );
          expect(request.headers['authorization'], 'Bearer secret-key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'test-model');
          expect(body['temperature'], 0.2);
          final messages = body['messages'] as List<dynamic>;
          expect(messages.first['role'], 'system');
          expect(messages.last['role'], 'user');
          expect(messages.last['content'], contains('Raw thought'));

          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '{"title":"Generated","body":"Draft body"}',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await provider.complete(
        const AiProviderRequest(
          task: 'murmur_to_note',
          contextPack: {
            'sources': ['Raw thought'],
          },
          outputSchema: {'type': 'object'},
        ),
      );

      expect(result.providerType, 'openaiCompatible');
      expect(result.structuredJson['title'], 'Generated');
      expect(result.structuredJson['body'], 'Draft body');
    });

    test('local HTTP provider sends context to local endpoint', () async {
      final provider = LocalHttpProvider(
        endpoint: Uri.parse('http://localhost:11434/ai'),
        model: 'local-model',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), 'http://localhost:11434/ai');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'local-model');
          expect(body['task'], 'discussion_summary');
          return http.Response(
            jsonEncode({
              'result': {'summary': 'Local summary'},
            }),
            200,
          );
        }),
      );

      final result = await provider.complete(
        const AiProviderRequest(
          task: 'discussion_summary',
          contextPack: {'discussion': 'Public thread'},
          outputSchema: {'type': 'object'},
        ),
      );

      expect(result.providerType, 'localHttp');
      expect(result.structuredJson['summary'], 'Local summary');
    });
  });
}
