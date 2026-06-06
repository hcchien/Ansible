import 'dart:convert';
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
    final payload = _encodeJsonPayload({
      'boardId': entityId,
      'slug': slug,
      'title': title,
      'description': description,
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
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
    final payload = _encodeJsonPayload({
      'boardId': boardId,
      'threadId': threadId,
      'content': content,
      'parentPostId': parentPostId,
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
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
    final payload = _encodeJsonPayload({
      'boardId': boardId,
      'threadId': entityId,
      'title': title,
      'description': description,
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
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

  /// Build an Op for publishing a standalone murmur (short-form content).
  ///
  /// The payload carries only the public/unlisted distributable subset — never
  /// private metadata such as private tags. Callers MUST only build ops for
  /// public/unlisted content (fail-closed at the publish boundary).
  static OpsQueueEntry createMurmur({
    required String authorDid,
    required String entityId,
    required String text,
    String visibility = 'public',
    String? tone,
    String? sourceType,
    DateTime? publishedAt,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'mode': 'murmur',
      'body': text,
      'visibility': visibility,
      'tone': tone,
      'sourceType': sourceType,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'publishedAt': (publishedAt ?? createdAt).toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'murmur',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  /// Build an Op for publishing a standalone note (long-form content).
  ///
  /// Notes carry an explicit [visibility] (public/unlisted). Private notes must
  /// not be published as ops.
  static OpsQueueEntry createNote({
    required String authorDid,
    required String entityId,
    required String body,
    required String visibility,
    String? title,
    DateTime? publishedAt,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'mode': 'note',
      'body': body,
      'title': title,
      'visibility': visibility,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'publishedAt': (publishedAt ?? createdAt).toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'note',
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

  /// Build an Op announcing a **federated** follow edge (follower -> target).
  ///
  /// Only federated follows are ever published; `localOnly` follows never leave
  /// the device. The AppView folds this into its follow graph and uses it to
  /// fan content out to the follower's home timeline. [entityId] is the stable
  /// edge identity (the target DID) so a later [deleteFollow] addresses the same
  /// edge.
  static OpsQueueEntry createFollow({
    required String followerDid,
    required String targetDid,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'targetDid': targetDid,
      'visibility': 'federated',
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: followerDid,
      entityType: 'follow',
      entityId: targetDid,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  /// Build an Op retracting a federated follow edge (unfollow). Mirrors
  /// [createFollow]'s [entityId] so the AppView removes the same graph edge.
  static OpsQueueEntry deleteFollow({
    required String followerDid,
    required String targetDid,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'targetDid': targetDid,
      'visibility': 'federated',
      'deletedAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: followerDid,
      entityType: 'follow',
      entityId: targetDid,
      opType: 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
    );
  }

  /// Build an Op announcing the author's **public** profile (the actor-directory
  /// entry that makes them findable). Only public fields are ever published;
  /// [entityId] is the author's own DID so updates address the same entry. The
  /// AppView folds this into its profiles table (last write wins by log id).
  static OpsQueueEntry createProfile({
    required String authorDid,
    String? handle,
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'handle': handle,
      'displayName': displayName,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'visibility': 'public',
      'updatedAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'profile',
      entityId: authorDid,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      createdAt: createdAt,
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
  /// The store package intentionally stays Flutter-free. Rust/Yrs delta
  /// generation is wired at the app/service layer; the repository layer keeps a
  /// deterministic JSON fallback that tests can run in pure Dart.
  static String _encodeYrsDelta(
    String entityId,
    String fieldName,
    String content,
  ) {
    return _encodeJsonPayload({fieldName: content});
  }

  static String _encodeJsonPayload(Map<String, Object?> data) {
    return base64Encode(utf8.encode(jsonEncode(data)));
  }
}
