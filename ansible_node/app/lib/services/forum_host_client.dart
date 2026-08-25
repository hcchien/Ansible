import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/protocol.dart';
import 'relay_identity_client.dart';

/// Encodes signed Forum Host payloads exactly as the Relay does: object keys
/// are sorted recursively, while array order is preserved.
String forumHostCanonicalJson(Object? value) =>
    jsonEncode(_canonicalForumHostValue(value));

Object? _canonicalForumHostValue(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    return <String, Object?>{
      for (final entry in entries)
        entry.key: _canonicalForumHostValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_canonicalForumHostValue).toList(growable: false);
  }
  return value;
}

class CreateHostedBoardIntent {
  static const type = 'io.trisaura.forum.createBoard';
  static const legacyVersion = 1;
  static const policyVersion = 2;

  final String intentId;
  final String authorDid;
  final String targetForumHost;
  final String signature;
  final String title;
  final String? description;

  /// Optional board posting policy, e.g. `{"min_post_tier": "verified_human"}`.
  /// Omitted from the payload when null or empty (ungated default).
  final Map<String, Object?>? postingPolicy;
  final Map<String, Object?>? accessPolicy;
  final String? contentVisibility;
  final Map<String, Object?>? federationPolicy;
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
    this.accessPolicy,
    this.contentVisibility,
    this.federationPolicy,
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
    Map<String, Object?>? accessPolicy,
    String? contentVisibility,
    Map<String, Object?>? federationPolicy,
  }) {
    final usesAccessPolicy = accessPolicy != null;
    if (usesAccessPolicy &&
        (contentVisibility == null || federationPolicy == null)) {
      throw ArgumentError(
        'createBoard v2 requires access policy, content visibility, and federation policy.',
      );
    }
    return {
      'action': 'create_board',
      'author_did': authorDid,
      'board': {
        if (description != null && description.isNotEmpty)
          'description': description,
        if (postingPolicy != null && postingPolicy.isNotEmpty)
          'posting_policy': postingPolicy,
        if (accessPolicy != null) 'access_policy': accessPolicy,
        if (contentVisibility != null) 'content_visibility': contentVisibility,
        if (federationPolicy != null) 'federation_policy': federationPolicy,
        'title': title,
      },
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'intent_id': intentId,
      'target_forum_host': targetForumHost,
      'type': type,
      'version': usesAccessPolicy ? policyVersion : legacyVersion,
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
        accessPolicy: accessPolicy,
        contentVisibility: contentVisibility,
        federationPolicy: federationPolicy,
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
      'signature': signature,
    };
  }
}

/// Signed `update_board` intent — creator-only hosted-board management
/// (`POST /api/v1/forum-host/boards/:board_id/update`). Same envelope as
/// [CreateHostedBoardIntent]; the payload names the target `board_id` plus a
/// `board` map carrying only the fields to change. The Forum Host verifies
/// the signature and that the author DID created the board.
class UpdateHostedBoardIntent {
  static const type = 'io.trisaura.forum.updateBoard';
  static const version = 1;

  final String intentId;
  final String authorDid;
  final String targetForumHost;
  final String signature;

  /// Host-side board identity (`hosted_board_id`), never the local board id.
  final String boardId;

  /// Fields to change; a null field is left untouched host-side. An empty
  /// [description] string clears the stored description.
  final String? title;
  final String? description;

  /// Replaces the stored posting policy when non-null (send the full desired
  /// policy map, e.g. `{"min_post_tier": "verified_human"}`; `{}` clears it).
  final Map<String, Object?>? postingPolicy;
  final DateTime createdAt;
  final DateTime expiresAt;

  const UpdateHostedBoardIntent({
    required this.intentId,
    required this.authorDid,
    required this.targetForumHost,
    required this.signature,
    required this.boardId,
    required this.createdAt,
    required this.expiresAt,
    this.title,
    this.description,
    this.postingPolicy,
  });

  /// Keys are listed alphabetically (nested map included) so the encoded
  /// JSON matches the relay's canonical sorted-key encoding for signature
  /// verification — same convention as [CreateHostedBoardIntent].
  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String targetForumHost,
    required String boardId,
    required DateTime createdAt,
    required DateTime expiresAt,
    String? title,
    String? description,
    Map<String, Object?>? postingPolicy,
  }) {
    return {
      'action': 'update_board',
      'author_did': authorDid,
      'board': {
        if (description != null) 'description': description,
        if (postingPolicy != null) 'posting_policy': postingPolicy,
        if (title != null) 'title': title,
      },
      'board_id': boardId,
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
        boardId: boardId,
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

/// Independently governed access-policy change. This is deliberately not part
/// of [UpdateHostedBoardIntent]: changing who may discover/read/post and
/// whether content is encrypted or federated has its own hash-chained,
/// threshold-approved history on the Forum Host.
class UpdateHostedBoardPolicyIntent {
  static const type = 'io.trisaura.forum.updateBoardPolicy';
  static const version = 1;

  final String intentId;
  final String authorDid;
  final String boardId;
  final String previousPolicyHash;
  final String targetForumHost;
  final Map<String, Object?> newPolicy;
  final Map<String, Object?> approvals;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime effectiveAt;
  final String signature;

  const UpdateHostedBoardPolicyIntent({
    required this.intentId,
    required this.authorDid,
    required this.boardId,
    required this.previousPolicyHash,
    required this.targetForumHost,
    required this.newPolicy,
    required this.createdAt,
    required this.expiresAt,
    required this.effectiveAt,
    required this.signature,
    this.approvals = const {},
  });

  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String boardId,
    required String previousPolicyHash,
    required String targetForumHost,
    required Map<String, Object?> newPolicy,
    required DateTime createdAt,
    required DateTime expiresAt,
    required DateTime effectiveAt,
    Map<String, Object?> approvals = const {},
  }) {
    final requiredKeys = {
      'access_policy',
      'content_visibility',
      'federation_policy',
    };
    if (newPolicy.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(newPolicy.keys.toSet()).isNotEmpty) {
      throw ArgumentError('newPolicy must contain the complete board policy');
    }
    return {
      'action': 'update_board_policy',
      'approvals': approvals,
      'author_did': authorDid,
      'board_id': boardId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'effective_at': effectiveAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'intent_id': intentId,
      'new_policy': newPolicy,
      'previous_policy_hash': previousPolicyHash,
      'target_forum_host': targetForumHost,
      'type': type,
      'version': version,
    };
  }

  Map<String, Object?> toJson() => {
    ...canonicalPayload(
      intentId: intentId,
      authorDid: authorDid,
      boardId: boardId,
      previousPolicyHash: previousPolicyHash,
      targetForumHost: targetForumHost,
      newPolicy: newPolicy,
      approvals: approvals,
      createdAt: createdAt,
      expiresAt: expiresAt,
      effectiveAt: effectiveAt,
    ),
    'signature': signature,
  };
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

/// One reason-coded moderation effect from a board's public moderation
/// state: a removed post or a locked thread.
class ModerationStateEntry {
  /// Op entity id of the moderated post/thread.
  final String targetRef;

  /// Reason code from the fixed enum ([ReportContentIntent.reasonCodes]).
  final String reasonCode;

  const ModerationStateEntry({
    required this.targetRef,
    required this.reasonCode,
  });
}

/// Public, reason-coded moderation state of a hosted board
/// (`GET /api/v1/forum-host/boards/:id/moderation-state`).
class BoardModerationState {
  final List<ModerationStateEntry> removedPosts;
  final List<ModerationStateEntry> lockedThreads;

  const BoardModerationState({
    required this.removedPosts,
    required this.lockedThreads,
  });
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

class CastPollVoteIntent {
  static const type = 'io.trisaura.forum.castPollVote';
  static const version = 1;

  const CastPollVoteIntent({
    required this.intentId,
    required this.authorDid,
    required this.targetForumHost,
    required this.boardId,
    required this.pollId,
    required this.optionId,
    required this.createdAt,
    required this.expiresAt,
    required this.signature,
  });

  final String intentId;
  final String authorDid;
  final String targetForumHost;
  final String boardId;
  final String pollId;
  final String optionId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String signature;

  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String targetForumHost,
    required String boardId,
    required String pollId,
    required String optionId,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) => {
    'action': 'cast_poll_vote',
    'author_did': authorDid,
    'board_id': boardId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'intent_id': intentId,
    'option_id': optionId,
    'poll_id': pollId,
    'target_forum_host': targetForumHost,
    'type': type,
    'version': version,
  };

  Map<String, Object?> toJson() => {
    ...canonicalPayload(
      intentId: intentId,
      authorDid: authorDid,
      targetForumHost: targetForumHost,
      boardId: boardId,
      pollId: pollId,
      optionId: optionId,
      createdAt: createdAt,
      expiresAt: expiresAt,
    ),
    'signature': signature,
  };
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
    return _boardsFrom(body);
  }

  /// Boards authored by [did] on this Forum Host. Lets a freshly-installed
  /// client re-list the boards it created (subscriptions are client-local and
  /// don't survive a reinstall, but board authorship is recorded host-side).
  Future<List<Map<String, dynamic>>> listBoardsCreatedBy(String did) async {
    final body = await _getJson(
      '/api/v1/forum-host/boards/created-by/${Uri.encodeComponent(did)}',
    );
    return _boardsFrom(body);
  }

  List<Map<String, dynamic>> _boardsFrom(Map<String, dynamic> body) {
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

  /// Updates a hosted board this DID created. Returns the updated board as
  /// serialized by the host (200). Idempotent for replayed intents.
  Future<Map<String, dynamic>> updateHostedBoard(
    UpdateHostedBoardIntent intent,
  ) async {
    return _postJson(
      '/api/v1/forum-host/boards/${Uri.encodeComponent(intent.boardId)}/update',
      intent.toJson(),
      expectedStatus: 200,
    );
  }

  Future<Map<String, dynamic>> updateHostedBoardPolicy(
    UpdateHostedBoardPolicyIntent intent,
  ) async {
    return _postJson(
      '/api/v1/forum-host/boards/${Uri.encodeComponent(intent.boardId)}/policy',
      intent.toJson(),
      expectedStatus: 200,
    );
  }

  Future<Map<String, dynamic>> castPollVote(
    CastPollVoteIntent intent, {
    Map<String, String> headers = const {},
  }) => _postJson(
    '/api/v1/forum-host/boards/${Uri.encodeComponent(intent.boardId)}/polls/${Uri.encodeComponent(intent.pollId)}/votes',
    intent.toJson(),
    expectedStatus: 201,
    headers: headers,
  );

  Future<Map<String, dynamic>> fetchPoll(
    String boardId,
    String pollId,
  ) => _getJson(
    '/api/v1/forum-host/boards/${Uri.encodeComponent(boardId)}/polls/${Uri.encodeComponent(pollId)}',
  );

  Future<List<Map<String, dynamic>>> getHostedBoardPolicyHistory(
    String boardId,
  ) async {
    final body = await _getJson(
      '/api/v1/forum-host/boards/${Uri.encodeComponent(boardId)}/policy-history',
    );
    final versions = body['versions'];
    if (versions is! List) {
      throw const FormatException('Expected board policy version list');
    }
    return versions
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  /// Submits a signed content report. 201 = created, 200 = collapsed into
  /// the reporter's existing open report for the same target.
  Future<ReportSubmission> submitReport(ReportContentIntent intent) async {
    final response = await _client
        .post(
          _endpoint('/api/v1/forum-host/reports'),
          headers: const {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
          },
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

  /// Fetches the public, reason-coded moderation state for a hosted board:
  /// removed-post tombstone refs and locked threads. Public by design — the
  /// affected author must be able to see the action and its reason
  /// (constitution Base Rule 6).
  Future<BoardModerationState> fetchBoardModerationState(
    String hostedBoardId,
  ) async {
    final body = await _getJson(
      '/api/v1/forum-host/boards/$hostedBoardId/moderation-state',
    );
    return BoardModerationState(
      removedPosts: _moderationEntries(body['removed_posts'], 'target_ref'),
      lockedThreads: _moderationEntries(body['locked_threads'], 'thread_id'),
    );
  }

  List<ModerationStateEntry> _moderationEntries(Object? raw, String refKey) {
    if (raw is! List) return const [];
    final entries = <ModerationStateEntry>[];
    for (final item in raw.whereType<Map>()) {
      final targetRef = item[refKey];
      final reasonCode = item['reason_code'];
      if (targetRef is String &&
          targetRef.isNotEmpty &&
          reasonCode is String &&
          reasonCode.isNotEmpty) {
        entries.add(
          ModerationStateEntry(targetRef: targetRef, reasonCode: reasonCode),
        );
      }
    }
    return entries;
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _client
        .get(_endpoint(path), headers: AnsibleProtocol.headers)
        .timeout(timeout);
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
    Map<String, String> headers = const {},
  }) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
            ...headers,
          },
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
