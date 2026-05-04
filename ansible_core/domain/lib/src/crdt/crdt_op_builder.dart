import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:ansible_store/ansible_store.dart';

/// Builds signed CRDT Op entries for the local OpsQueue.
///
/// V1.1 Comp B: Q1 uses JSON-encoded payloads (base64).
/// Q2 will replace payload encoding with real Yrs binary deltas (Rust FFI).
/// Q2 will replace stub signature with real Ed25519 from ansible_did.
class CrdtOpBuilder {
  static const _uuid = Uuid();

  /// Build an Op for creating a new post.
  static OpsQueueEntry createPost({
    required String authorDid,
    required String boardId,
    required String threadId,
    required String content,
    String? parentPostId,
  }) {
    final opId = _uuid.v4();
    final entityId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final payload = _encodePayload({
      'boardId': boardId,
      'threadId': threadId,
      'content': content,
      'parentPostId': parentPostId,
      'createdAt': now,
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'post',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: DateTime.now(),
    );
  }

  /// Build an Op for creating a new thread.
  static OpsQueueEntry createThread({
    required String authorDid,
    required String boardId,
    required String title,
    String? description,
  }) {
    final opId = _uuid.v4();
    final entityId = _uuid.v4();
    final payload = _encodePayload({
      'boardId': boardId,
      'title': title,
      'description': description,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'thread',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: DateTime.now(),
    );
  }

  /// Build an Op for editing a post (CRDT update delta).
  static OpsQueueEntry updatePost({
    required String authorDid,
    required String entityId,
    required String newContent,
  }) {
    final opId = _uuid.v4();
    final payload = _encodePayload({
      'content': newContent,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'post',
      entityId: entityId,
      opType: 'update',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: DateTime.now(),
    );
  }

  /// Decode a payload back to a Map.
  static Map<String, dynamic> decodePayload(String payload) {
    return jsonDecode(utf8.decode(base64Decode(payload))) as Map<String, dynamic>;
  }

  /// Stub signature — replaced by real Ed25519 from ansible_did in Q2.
  static String _stubSignature(String opId, String payload) {
    // TODO(Q2): final sig = await DidSigner.sign(utf8.encode(opId) + base64.decode(payload));
    return 'stub_sig_${opId.substring(0, 8)}';
  }

  static String _encodePayload(Map<String, dynamic> data) {
    // Q1: JSON → base64. Q2: replace with Yrs binary delta via Rust FFI.
    return base64Encode(utf8.encode(jsonEncode(data)));
  }
}
