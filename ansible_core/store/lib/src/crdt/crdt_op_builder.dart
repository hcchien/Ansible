import 'dart:convert';
import 'package:ansible_did/ansible_did.dart';
import 'package:uuid/uuid.dart';
import '../entities/ops_queue.dart';

/// Builds signed CRDT Op entries for the local OpsQueue.
///
/// V1.1 Comp B: Q2 uses Yrs binary delta payloads via Rust FFI.
/// Falls back to JSON→base64 encoding when the FFI throws UnimplementedError.
/// Q2 will replace stub signature with real Ed25519 from ansible_did.
class CrdtOpBuilder {
  static const _uuid = Uuid();

  static OpsQueueEntry createBoard({
    required String authorDid,
    required String entityId,
    required String slug,
    required String title,
    String? description,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    // Use Yrs delta for the primary 'title' field; metadata falls back to JSON.
    final payload = _encodeYrsDelta(entityId, 'title', title);
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'board',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  /// Build an Op for creating a new post.
  static OpsQueueEntry createPost({
    required String authorDid,
    required String entityId,
    required String boardId,
    required String threadId,
    required String content,
    String? parentPostId,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeYrsDelta(entityId, 'content', content);
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'post',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  /// Build an Op for creating a new thread.
  static OpsQueueEntry createThread({
    required String authorDid,
    required String entityId,
    required String boardId,
    required String title,
    String? description,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeYrsDelta(entityId, 'title', title);
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'thread',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  /// Build an Op for editing a post (CRDT update delta).
  static OpsQueueEntry updatePost({
    required String authorDid,
    required String entityId,
    required String newContent,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeYrsDelta(entityId, 'content', newContent);
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

  static OpsQueueEntry deletePost({
    required String authorDid,
    required String entityId,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeJsonPayload({
      'deletedAt': DateTime.now().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'post',
      entityId: entityId,
      opType: 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: DateTime.now(),
    );
  }

  static OpsQueueEntry createReaction({
    required String authorDid,
    required String entityId,
    required String targetType,
    required String targetId,
    required String reactionType,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeYrsDelta(entityId, 'reactionType', reactionType);
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'reaction',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  static OpsQueueEntry deleteReaction({
    required String authorDid,
    required String entityId,
    required String targetType,
    required String targetId,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeJsonPayload({
      'targetType': targetType,
      'targetId': targetId,
      'deletedAt': DateTime.now().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'reaction',
      entityId: entityId,
      opType: 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: DateTime.now(),
    );
  }

  /// Decode a payload back to a Map.
  static Map<String, dynamic> decodePayload(String payload) {
    return jsonDecode(utf8.decode(base64Decode(payload)))
        as Map<String, dynamic>;
  }

  /// Stub signature — replaced by real Ed25519 from ansible_did in Q2.
  static String _stubSignature(String opId, String payload) {
    // TODO(Q2): final sig = await DidSigner.sign(utf8.encode(opId) + base64.decode(payload));
    return 'stub_sig_${opId.substring(0, 8)}';
  }

  /// Encode a Yrs binary delta for [fieldName] / [content] of [entityId].
  ///
  /// Calls the Rust FFI to init the Yrs doc and insert text, returning the
  /// base64-encoded binary delta. Falls back to JSON→base64 when codegen has
  /// not yet been run (UnimplementedError).
  static String _encodeYrsDelta(String entityId, String fieldName, String content) {
    try {
      RustLib.instance.apiCrdtInitDoc(entityId: entityId);
      return RustLib.instance.apiCrdtInsertText(
        entityId: entityId,
        fieldName: fieldName,
        content: content,
      );
    } on UnimplementedError {
      // Codegen not yet run — fall back to Q1 JSON→base64 encoding
      return _encodeJsonPayload({fieldName: content});
    }
  }

  static String _encodeJsonPayload(Map<String, Object?> data) {
    return base64Encode(utf8.encode(jsonEncode(data)));
  }
}
