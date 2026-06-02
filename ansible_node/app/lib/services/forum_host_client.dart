import 'dart:convert';

import 'package:http/http.dart' as http;

import 'relay_identity_client.dart';

class CreateHostedBoardIntent {
  static const type = 'io.trisaura.forum.createBoard';
  static const version = 1;

  final String intentId;
  final String authorDid;
  final String targetForumHost;
  final String signature;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime expiresAt;

  const CreateHostedBoardIntent({
    required this.intentId,
    required this.authorDid,
    required this.targetForumHost,
    required this.signature,
    required this.title,
    required this.createdAt,
    required this.expiresAt,
    this.description,
  });

  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String targetForumHost,
    required String title,
    required DateTime createdAt,
    required DateTime expiresAt,
    String? description,
  }) {
    return {
      'action': 'create_board',
      'author_did': authorDid,
      'board': {
        if (description != null && description.isNotEmpty)
          'description': description,
        'title': title,
      },
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'intent_id': intentId,
      'target_forum_host': targetForumHost,
      'type': type,
      'version': version,
    };
  }

  Map<String, Object?> toJson() {
    return {
      ...canonicalPayload(
        intentId: intentId,
        authorDid: authorDid,
        targetForumHost: targetForumHost,
        title: title,
        description: description,
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
      'signature': signature,
    };
  }
}

class ForumHostException implements Exception {
  final int statusCode;
  final String? error;
  final String? message;
  final Map<String, dynamic> body;

  const ForumHostException({
    required this.statusCode,
    required this.body,
    this.error,
    this.message,
  });

  @override
  String toString() {
    final label = error ?? 'forum_host_error';
    final detail = message == null ? '' : ': $message';
    return 'ForumHostException($statusCode $label$detail)';
  }
}

class ForumHostClient {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  ForumHostClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  Future<Map<String, dynamic>> getHostInfo() async {
    return _getJson('/api/v1/forum-host');
  }

  Future<List<Map<String, dynamic>>> listHostedBoards() async {
    final body = await _getJson('/api/v1/forum-host/boards');
    final boards = body['boards'];
    if (boards is! List) {
      throw const FormatException('Expected boards list from Forum Host');
    }
    return boards
        .whereType<Map>()
        .map((board) => Map<String, dynamic>.from(board))
        .toList();
  }

  Future<Map<String, dynamic>> createHostedBoard(
    CreateHostedBoardIntent intent,
  ) async {
    return _postJson(
      '/api/v1/forum-host/boards',
      intent.toJson(),
      expectedStatus: 201,
    );
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _client.get(_endpoint(path)).timeout(timeout);
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response.statusCode, body);
    }
    return body;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body, {
    required int expectedStatus,
  }) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final decoded = _decodeObject(response.body);
    if (response.statusCode != expectedStatus) {
      throw _toException(response.statusCode, decoded);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException(
      'Expected JSON object from Forum Host: $responseBody',
    );
  }

  ForumHostException _toException(int statusCode, Map<String, dynamic> body) {
    return ForumHostException(
      statusCode: statusCode,
      body: body,
      error: body['error'] as String?,
      message: body['message'] as String?,
    );
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
