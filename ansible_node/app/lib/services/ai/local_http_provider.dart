import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';

class LocalHttpProvider implements AiProvider {
  final Uri endpoint;
  final String model;
  final http.Client _client;

  LocalHttpProvider({
    required this.endpoint,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<AiProviderResult> complete(AiProviderRequest request) async {
    final response = await _client.post(
      endpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'task': request.task,
        'contextPack': request.contextPack,
        'outputSchema': request.outputSchema,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(
        'Local HTTP provider returned ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'];
    if (result is Map<String, dynamic>) {
      return AiProviderResult(
        providerType: 'localHttp',
        structuredJson: result,
        rawText: response.body,
      );
    }
    return AiProviderResult(
      providerType: 'localHttp',
      structuredJson: body,
      rawText: response.body,
    );
  }
}
