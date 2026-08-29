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

  /// Op payload format version stamped on every locally authored op
  /// (service architecture plan, Phase 0 — API versioning). Mirrors the
  /// relay's `AnsibleRelay.Protocol.current_version()`.
  static const int opSchemaVersion = 1;

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
      schemaVersion: opSchemaVersion,
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
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  /// Builds a private-board post op. Only routing metadata is cleartext; the
  /// title/body lives inside [privateEnvelope] and is never sent separately.
  static OpsQueueEntry createPrivatePost({
    required String authorDid,
    required String entityId,
    required String boardId,
    required String threadId,
    required Map<String, Object?> privateEnvelope,
    String? parentPostId,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'boardId': boardId,
      'threadId': threadId,
      'parentPostId': parentPostId,
      'private_envelope': privateEnvelope,
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'post',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  /// Build an Op for a comment on standalone content (murmur/note).
  ///
  /// A distinct `comment` entity type — NOT a `post` — so comments never collide
  /// with the forum thread/post model (board-less posts were being mis-synced as
  /// phantom forum threads). [targetId] is the commented content's entity id;
  /// it is also mirrored to `threadId` so the AppView can index/serve comments
  /// via `GET /api/v1/thread/:thread_id`.
  static OpsQueueEntry createComment({
    required String authorDid,
    required String entityId,
    required String targetId,
    required String content,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'targetId': targetId,
      'threadId': targetId,
      'content': content,
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'comment',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  /// Build an Op for editing a comment (CRDT content delta on a `comment`).
  static OpsQueueEntry updateComment({
    required String authorDid,
    required String entityId,
    required String newContent,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeYrsDelta(entityId, 'content', newContent);
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'comment',
      entityId: entityId,
      opType: 'update',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: DateTime.now(),
    );
  }

  /// Build an Op for deleting a comment.
  static OpsQueueEntry deleteComment({
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
      entityType: 'comment',
      entityId: entityId,
      opType: 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: DateTime.now(),
    );
  }

  /// Build an Op for creating a new thread.
  static OpsQueueEntry createThread({
    required String authorDid,
    required String entityId,
    required String boardId,
    required String title,
    String? description,
    Map<String, Object?>? poll,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'boardId': boardId,
      'threadId': entityId,
      'title': title,
      'description': description,
      if (poll != null) 'poll': poll,
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
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  static OpsQueueEntry createPrivateThread({
    required String authorDid,
    required String entityId,
    required String boardId,
    required Map<String, Object?> privateEnvelope,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'boardId': boardId,
      'threadId': entityId,
      'private_envelope': privateEnvelope,
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'thread',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  /// Build an Op for changing a thread's title. The Relay verifies that the
  /// signer is the author of the original insert op before accepting it.
  static OpsQueueEntry updateThread({
    required String authorDid,
    required String entityId,
    required String newTitle,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeJsonPayload({
      'title': newTitle,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'thread',
      entityId: entityId,
      opType: 'update',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: DateTime.now(),
    );
  }

  /// Build an author-signed tombstone for a whole thread.
  static OpsQueueEntry deleteThread({
    required String authorDid,
    required String entityId,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeJsonPayload({
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'thread',
      entityId: entityId,
      opType: 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: DateTime.now(),
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
      schemaVersion: opSchemaVersion,
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
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  /// Publishes a source-backed Community Note pinned to one exact public
  /// content revision. Ratings are not ops; they use the private Forum Host
  /// signed-intent rail.
  static OpsQueueEntry createContextNote({
    required String authorDid,
    required String entityId,
    required String targetEntityType,
    required String targetEntityId,
    required String targetOpId,
    required String targetContentHash,
    required String body,
    required List<Map<String, String>> sources,
    String? boardId,
  }) {
    return _contextNoteOp(
      authorDid: authorDid,
      entityId: entityId,
      opType: 'insert',
      targetEntityType: targetEntityType,
      targetEntityId: targetEntityId,
      targetOpId: targetOpId,
      targetContentHash: targetContentHash,
      body: body,
      sources: sources,
      boardId: boardId,
    );
  }

  /// Updates only the explanation/sources. The immutable target tuple must be
  /// supplied unchanged so Relay and AppView can reject retargeting.
  static OpsQueueEntry updateContextNote({
    required String authorDid,
    required String entityId,
    required String targetEntityType,
    required String targetEntityId,
    required String targetOpId,
    required String targetContentHash,
    required String body,
    required List<Map<String, String>> sources,
    String? boardId,
  }) {
    return _contextNoteOp(
      authorDid: authorDid,
      entityId: entityId,
      opType: 'update',
      targetEntityType: targetEntityType,
      targetEntityId: targetEntityId,
      targetOpId: targetOpId,
      targetContentHash: targetContentHash,
      body: body,
      sources: sources,
      boardId: boardId,
    );
  }

  static OpsQueueEntry deleteContextNote({
    required String authorDid,
    required String entityId,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'deletedAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'context_note',
      entityId: entityId,
      opType: 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  static OpsQueueEntry _contextNoteOp({
    required String authorDid,
    required String entityId,
    required String opType,
    required String targetEntityType,
    required String targetEntityId,
    required String targetOpId,
    required String targetContentHash,
    required String body,
    required List<Map<String, String>> sources,
    String? boardId,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'targetEntityType': targetEntityType,
      'targetEntityId': targetEntityId,
      'targetOpId': targetOpId,
      'targetContentHash': targetContentHash,
      if (boardId != null && boardId.isNotEmpty) 'boardId': boardId,
      'body': body,
      'sources': sources,
      'visibility': 'public',
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'context_note',
      entityId: entityId,
      opType: opType,
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
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
      schemaVersion: opSchemaVersion,
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
      schemaVersion: opSchemaVersion,
      createdAt: DateTime.now(),
    );
  }

  static OpsQueueEntry createReaction({
    required String authorDid,
    required String entityId,
    required String targetType,
    required String targetId,
    required String reactionType,
    String? boardId,
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    // Reactions are immutable facts rather than a mutable document, so their
    // signed payload must carry enough routing data for another device to
    // materialize and scope the reaction without guessing from local state.
    final payload = _encodeJsonPayload({
      'targetType': targetType,
      'targetId': targetId,
      'reactionType': reactionType,
      if (boardId != null && boardId.isNotEmpty) 'boardId': boardId,
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'reaction',
      entityId: entityId,
      opType: 'insert',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  static OpsQueueEntry deleteReaction({
    required String authorDid,
    required String entityId,
    required String targetType,
    required String targetId,
    String? boardId,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeJsonPayload({
      'targetType': targetType,
      'targetId': targetId,
      if (boardId != null && boardId.isNotEmpty) 'boardId': boardId,
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
      schemaVersion: opSchemaVersion,
      createdAt: DateTime.now(),
    );
  }

  /// Change the single active reaction for an author/target pair without
  /// creating another countable entity. The entity id remains stable, so every
  /// replica replaces the prior type rather than incrementing both types.
  static OpsQueueEntry updateReaction({
    required String authorDid,
    required String entityId,
    required String targetType,
    required String targetId,
    required String reactionType,
    String? boardId,
  }) {
    final opId = _uuid.v4();
    final payload = _encodeJsonPayload({
      'targetType': targetType,
      'targetId': targetId,
      'reactionType': reactionType,
      if (boardId != null && boardId.isNotEmpty) 'boardId': boardId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: authorDid,
      entityType: 'reaction',
      entityId: entityId,
      opType: 'update',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
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
      'state': 'requested',
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
      schemaVersion: opSchemaVersion,
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
      schemaVersion: opSchemaVersion,
      createdAt: createdAt,
    );
  }

  /// Target-authored relationship VC accepting or rejecting a follow request.
  /// It intentionally contains no Wallet or identity-credential claims.
  static OpsQueueEntry createFollowGrant({
    required String targetDid,
    required String followerDid,
    required String requestOpId,
    required bool accepted,
    String denialReason = 'rejected',
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final payload = _encodeJsonPayload({
      'requestOpId': requestOpId,
      'followerDid': followerDid,
      'targetDid': targetDid,
      if (!accepted) 'reason': denialReason,
      if (accepted)
        'credential': {
          '@context': ['https://www.w3.org/ns/credentials/v2'],
          'type': ['VerifiableCredential', 'FollowGrantCredential'],
          'issuer': targetDid,
          'issuanceDate': createdAt.toIso8601String(),
          'credentialSubject': {
            'id': followerDid,
            'targetDid': targetDid,
            'relationship': 'approved_follower',
          },
        },
      'createdAt': createdAt.toIso8601String(),
    });
    return OpsQueueEntry(
      opId: opId,
      authorDid: targetDid,
      entityType: 'follow_grant',
      entityId: followerDid,
      opType: accepted ? 'insert' : 'delete',
      payload: payload,
      signature: _stubSignature(opId, payload),
      schemaVersion: opSchemaVersion,
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
    List<String> credentialTypes = const <String>[],
  }) {
    final opId = _uuid.v4();
    final createdAt = DateTime.now();
    final payload = _encodeJsonPayload({
      'handle': handle,
      'displayName': displayName,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'credentialTypes': credentialTypes,
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
      schemaVersion: opSchemaVersion,
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
