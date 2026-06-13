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

  /// Optional board posting policy, e.g. `{"min_post_tier": "verified_human"}`.
  /// Omitted from the payload when null or empty (ungated default).
  final Map<String, Object?>? postingPolicy;
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
    this.postingPolicy,
  });

  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String targetForumHost,
    required String title,
    required DateTime createdAt,
    required DateTime expiresAt,
    String? description,
    Map<String, Object?>? postingPolicy,
  }) {
    return {
      'action': 'create_board',
      'author_did': authorDid,
      'board': {
        if (description != null && description.isNotEmpty)
          'description': description,
        if (postingPolicy != null && postingPolicy.isNotEmpty)
          'posting_policy': postingPolicy,
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
        postingPolicy: postingPolicy,
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
      'signature': signature,
    };
  }
}

/// Signed `report_content` intent — the app rail for reporting hosted
/// board content to its Forum Host (`POST /api/v1/forum-host/reports`).
///
/// Reports are accountable (signed by the reporter DID) and reason-coded;
/// the host's moderators act on them host-side. See
/// docs/superpowers/plans/2026-06-12-content-reporting-moderation.md.
class ReportContentIntent {
  static const type = 'io.trisaura.forum.reportContent';
  static const version = 1;

  /// Reason codes accepted by the relay (one module relay-side).
  static const reasonCodes = [
    'spam',
    'harassment',
    'illegal_content',
    'off_topic',
    'impersonation',
    'other',
  ];

  final String intentId;
  final String authorDid;
  final String targetForumHost;
  final String signature;
  final String targetKind; // "post" | "thread"
  final String targetRef;
  final String boardId; // hosted board id (host-side identity)
  final String reasonCode;
  final String? note;
  final DateTime createdAt;
  final DateTime expiresAt;

  const ReportContentIntent({
    required this.intentId,
    required this.authorDid,
    required this.targetForumHost,
    required this.signature,
    required this.targetKind,
    required this.targetRef,
    required this.boardId,
    required this.reasonCode,
    required this.createdAt,
    required this.expiresAt,
    this.note,
  });

  /// Keys are listed alphabetically (nested map included) so the encoded
  /// JSON matches the relay's canonical sorted-key encoding for signature
  /// verification — same convention as [CreateHostedBoardIntent].
  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String targetForumHost,
    required String targetKind,
    required String targetRef,
    required String boardId,
    required String reasonCode,
    required DateTime createdAt,
    required DateTime expiresAt,
    String? note,
  }) {
    return {
      'action': 'report_content',
      'author_did': authorDid,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'intent_id': intentId,
      'report': {
        'board_id': boardId,
        if (note != null && note.isNotEmpty) 'note': note,
        'reason_code': reasonCode,
        'target_kind': targetKind,
        'target_ref': targetRef,
      },
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
        targetKind: targetKind,
        targetRef: targetRef,
        boardId: boardId,
        reasonCode: reasonCode,
        note: note,
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
      'signature': signature,
    };
  }
}

/// Outcome of submitting a report: created, or collapsed into an existing
/// open report (the relay returns 200 instead of 201 for duplicates).
class ReportSubmission {
  final bool duplicate;
  final Map<String, dynamic> report;

  const ReportSubmission({required this.duplicate, required this.report});
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

  /// Submits a signed content report. 201 = created, 200 = collapsed into
  /// the reporter's existing open report for the same target.
  Future<ReportSubmission> submitReport(ReportContentIntent intent) async {
    final response = await _client
        .post(
          _endpoint('/api/v1/forum-host/reports'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(intent.toJson()),
        )
        .timeout(timeout);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _toException(
        response.statusCode,
        _decodeObjectOrEmpty(response.body),
      );
    }
    final body = _decodeObject(response.body);
    return ReportSubmission(
      duplicate: response.statusCode == 200,
      report: Map<String, dynamic>.from(body['report'] as Map? ?? body),
    );
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _client.get(_endpoint(path)).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(
        response.statusCode,
        _decodeObjectOrEmpty(response.body),
      );
    }
    final body = _decodeObject(response.body);
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
    if (response.statusCode != expectedStatus) {
      throw _toException(
        response.statusCode,
        _decodeObjectOrEmpty(response.body),
      );
    }
    final decoded = _decodeObject(response.body);
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
    return Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '$basePath$path',
    );
  }

  void close() {
    _client.close();
  }
}

Map<String, dynamic> _decodeObjectOrEmpty(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}
