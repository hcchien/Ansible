import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

import '../config/protocol.dart';
import 'relay_identity_client.dart';

class RelayOpsException implements Exception {
  final int statusCode;
  final String? error;
  final String? message;
  final Map<String, dynamic> body;

  const RelayOpsException({
    required this.statusCode,
    required this.body,
    this.error,
    this.message,
  });

  bool get isPermanentRejection =>
      statusCode == 422 || error == 'invalid_signature' || statusCode == 409;

  bool get isPolicyBlock => statusCode == 403;

  bool get isDuplicate => statusCode == 409;

  @override
  String toString() {
    final label = error ?? 'relay_ops_error';
    final detail = message == null ? '' : ': $message';
    return 'RelayOpsException($statusCode $label$detail)';
  }
}

class RelayOpsClient {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  RelayOpsClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.accessToken,
    this.requestHeaders,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  final String? accessToken;
  final Future<Map<String, String>> Function(OpsQueueEntry, Uri)?
  requestHeaders;

  Future<int> ingest(OpsQueueEntry entry) async {
    final endpoint = _endpoint('/api/v1/ops');
    final scopedHeaders =
        await requestHeaders?.call(entry, endpoint) ?? const {};
    final response = await _client
        .post(
          endpoint,
          headers: {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
            ...scopedHeaders,
          },
          body: jsonEncode(_entryToRelayJson(entry)),
        )
        .timeout(timeout);

    final body = _decodeObject(response.body);
    if (response.statusCode != 202) {
      throw RelayOpsException(
        statusCode: response.statusCode,
        body: body,
        error: body['error'] as String?,
        message: body['message'] as String?,
      );
    }

    return body['log_id'] as int;
  }

  Map<String, Object?> _entryToRelayJson(OpsQueueEntry entry) {
    return {
      'op_id': entry.opId,
      'author_did': entry.authorDid,
      'entity_type': entry.entityType,
      'entity_id': entry.entityId,
      'op_type': entry.opType,
      'payload': entry.payload,
      'signature': entry.signature,
      // Op payload format version (Phase 0 — API versioning). Outside the
      // signing payload by design, so the signature stays valid.
      'schema_version': entry.schemaVersion,
    };
  }

  Map<String, dynamic> _decodeObject(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Expected JSON object from Relay: $responseBody');
  }

  Uri _endpoint(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$path');
  }

  void close() {
    _client.close();
  }
}
