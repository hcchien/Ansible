import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../config/protocol.dart';
import 'blocked_author_store.dart';
import 'forum_host_client.dart';

typedef SafetyPayloadSigner = Future<String> Function(List<int> payload);

abstract interface class SafetyReportTransport {
  Future<void> send(Map<String, Object?> body);
}

class HttpSafetyReportTransport implements SafetyReportTransport {
  HttpSafetyReportTransport({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<void> send(Map<String, Object?> body) async {
    final origin = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await _client.post(
      Uri.parse('$origin/api/v1/safety/reports'),
      headers: const {
        'content-type': 'application/json',
        ...AnsibleProtocol.headers,
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SafetyReportException(response.statusCode);
    }
  }
}

class SafetyReportException implements Exception {
  const SafetyReportException(this.statusCode);
  final int statusCode;
}

/// Explicit report/block orchestration. Blocking is persisted locally first so
/// the author disappears immediately even when the developer notification
/// cannot be delivered. A delivery failure is surfaced to the user and never
/// rolls back their local safety choice.
class SafetyActions {
  SafetyActions({
    BlockedAuthorStore blockedAuthors = const BlockedAuthorStore(),
    SafetyReportTransport? transport,
    SafetyPayloadSigner? signer,
    String relayBaseUrl = AppEnvironment.defaultRelayBaseUrl,
  }) : _blockedAuthors = blockedAuthors,
       _transport =
           transport ?? HttpSafetyReportTransport(baseUrl: relayBaseUrl),
       _signer =
           signer ??
           ((payload) => DidSignerImpl()
               .sign(payload)
               .then((signature) => signature.hex)),
       _relayBaseUrl = relayBaseUrl;

  final BlockedAuthorStore _blockedAuthors;
  final SafetyReportTransport _transport;
  final SafetyPayloadSigner _signer;
  final String _relayBaseUrl;

  Future<Set<String>> blockedAuthors(String ownerDid) =>
      _blockedAuthors.load(ownerDid);

  Future<void> unblock({
    required String reporterDid,
    required String subjectDid,
  }) => _blockedAuthors.unblock(reporterDid, subjectDid);

  Future<void> reportContent({
    required String reporterDid,
    required String subjectDid,
    required String targetKind,
    required String targetRef,
    required String reasonCode,
    String? note,
  }) {
    return _send(
      eventType: 'report_content',
      reporterDid: reporterDid,
      subjectDid: subjectDid,
      targetKind: targetKind,
      targetRef: targetRef,
      reasonCode: reasonCode,
      note: note,
    );
  }

  Future<void> blockAndReport({
    required String reporterDid,
    required String subjectDid,
    required String targetKind,
    required String targetRef,
    required String reasonCode,
    String? note,
  }) async {
    await _blockedAuthors.block(reporterDid, subjectDid);
    await _send(
      eventType: 'block_user',
      reporterDid: reporterDid,
      subjectDid: subjectDid,
      targetKind: targetKind,
      targetRef: targetRef,
      reasonCode: reasonCode,
      note: note,
    );
  }

  Future<void> _send({
    required String eventType,
    required String reporterDid,
    required String subjectDid,
    required String targetKind,
    required String targetRef,
    required String reasonCode,
    String? note,
  }) async {
    final createdAt = DateTime.now().toUtc();
    final payload = canonicalPayload(
      eventType: eventType,
      intentId: const Uuid().v4(),
      reporterDid: reporterDid,
      targetRelay: _relayBaseUrl,
      subjectDid: subjectDid,
      targetKind: targetKind,
      targetRef: targetRef,
      reasonCode: reasonCode,
      note: note,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    final signature = await _signer(
      utf8.encode(forumHostCanonicalJson(payload)),
    );
    await _transport.send({...payload, 'signature': signature});
  }

  static Map<String, Object?> canonicalPayload({
    required String eventType,
    required String intentId,
    required String reporterDid,
    required String targetRelay,
    required String subjectDid,
    required String targetKind,
    required String targetRef,
    required String reasonCode,
    required DateTime createdAt,
    required DateTime expiresAt,
    String? note,
  }) {
    return {
      'action': eventType,
      'author_did': reporterDid,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'intent_id': intentId,
      'report': {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'reason_code': reasonCode,
        'subject_did': subjectDid,
        'target_kind': targetKind,
        'target_ref': targetRef,
      },
      'target_relay': targetRelay,
      'type': 'io.trisaura.safety.report',
      'version': 1,
    };
  }
}
