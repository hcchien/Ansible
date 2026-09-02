import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('CrdtOpBuilder mentions', () {
    test('post and comment carry unique capped public DID recipients', () {
      final mentionDids = [
        'did:key:bob',
        'did:key:bob',
        'did:key:alice',
        'not-a-did',
        for (var i = 0; i < 12; i++) 'did:key:user-$i',
      ];
      final post = CrdtOpBuilder.createPost(
        authorDid: 'did:key:alice',
        entityId: 'post-mention',
        boardId: 'board-1',
        threadId: 'thread-1',
        content: '@bob hello',
        mentionDids: mentionDids,
      );
      final comment = CrdtOpBuilder.createComment(
        authorDid: 'did:key:alice',
        entityId: 'comment-mention',
        targetId: 'note-1',
        content: '@bob hello',
        mentionDids: const ['did:key:bob'],
      );

      final postMentions =
          CrdtOpBuilder.decodePayload(post.payload)['mentionDids'] as List;
      expect(postMentions, hasLength(10));
      expect(postMentions.first, 'did:key:bob');
      expect(postMentions, isNot(contains('did:key:alice')));
      expect(postMentions, isNot(contains('not-a-did')));
      expect(CrdtOpBuilder.decodePayload(comment.payload)['mentionDids'], [
        'did:key:bob',
      ]);
    });
  });

  group('CrdtOpBuilder reaction', () {
    test('createReaction carries signed target and board routing metadata', () {
      final op = CrdtOpBuilder.createReaction(
        authorDid: 'did:key:alice',
        entityId: 'reaction-1',
        targetType: 'thread',
        targetId: 'thread-1',
        reactionType: 'thumbsUp',
        boardId: 'board-1',
      );

      expect(op.entityType, 'reaction');
      expect(op.opType, 'insert');
      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['targetType'], 'thread');
      expect(payload['targetId'], 'thread-1');
      expect(payload['reactionType'], 'thumbsUp');
      expect(payload['boardId'], 'board-1');
      expect(payload.containsKey('createdAt'), isTrue);
    });

    test('deleteReaction preserves target and board routing metadata', () {
      final op = CrdtOpBuilder.deleteReaction(
        authorDid: 'did:key:alice',
        entityId: 'reaction-1',
        targetType: 'thread',
        targetId: 'thread-1',
        boardId: 'board-1',
      );

      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['targetType'], 'thread');
      expect(payload['targetId'], 'thread-1');
      expect(payload['boardId'], 'board-1');
    });

    test(
      'updateReaction retains its entity id and carries the replacement',
      () {
        final op = CrdtOpBuilder.updateReaction(
          authorDid: 'did:key:alice',
          entityId: 'reaction-1',
          targetType: 'thread',
          targetId: 'thread-1',
          reactionType: 'happy',
          boardId: 'board-1',
        );

        expect(op.entityType, 'reaction');
        expect(op.entityId, 'reaction-1');
        expect(op.opType, 'update');
        final payload = CrdtOpBuilder.decodePayload(op.payload);
        expect(payload['reactionType'], 'happy');
        expect(payload['targetId'], 'thread-1');
      },
    );
  });

  group('CrdtOpBuilder murmur/note', () {
    test(
      'createMurmur builds a murmur op with a public distributable payload',
      () {
        final op = CrdtOpBuilder.createMurmur(
          authorDid: 'did:key:alice',
          entityId: 'murmur-1',
          text: 'a passing thought',
          tone: 'note',
          sourceType: 'typed',
        );

        expect(op.entityType, 'murmur');
        expect(op.opType, 'insert');
        expect(op.authorDid, 'did:key:alice');
        expect(op.entityId, 'murmur-1');

        final payload = CrdtOpBuilder.decodePayload(op.payload);
        expect(payload['mode'], 'murmur');
        expect(payload['body'], 'a passing thought');
        expect(payload['visibility'], 'public');
        expect(payload['tone'], 'note');
        expect(payload['sourceType'], 'typed');
        expect(payload.containsKey('createdAt'), isTrue);
        // Private metadata must never enter the op payload.
        expect(payload.containsKey('privateTagsJson'), isFalse);
      },
    );

    test('createNote builds a note op carrying its visibility', () {
      final op = CrdtOpBuilder.createNote(
        authorDid: 'did:key:alice',
        entityId: 'note-1',
        body: 'a longer essay',
        title: 'On Things',
        visibility: 'unlisted',
      );

      expect(op.entityType, 'note');
      expect(op.opType, 'insert');

      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['mode'], 'note');
      expect(payload['body'], 'a longer essay');
      expect(payload['title'], 'On Things');
      expect(payload['visibility'], 'unlisted');
      expect(payload.containsKey('createdAt'), isTrue);
    });

    test('createMurmur accepts unlisted visibility', () {
      final op = CrdtOpBuilder.createMurmur(
        authorDid: 'did:key:alice',
        entityId: 'm2',
        text: 'hi',
        visibility: 'unlisted',
      );
      expect(CrdtOpBuilder.decodePayload(op.payload)['visibility'], 'unlisted');
    });
  });

  group('CrdtOpBuilder Community Notes', () {
    test('createContextNote pins an exact target and public sources', () {
      final op = CrdtOpBuilder.createContextNote(
        authorDid: 'did:key:alice',
        entityId: 'context-note-1',
        targetEntityType: 'murmur',
        targetEntityId: 'murmur-1',
        targetOpId: 'op-target-1',
        targetContentHash: 'sha256:${List.filled(64, 'a').join()}',
        body: 'Additional context',
        sources: const [
          {'url': 'https://example.test/source', 'title': 'Source'},
        ],
      );

      expect(op.entityType, 'context_note');
      expect(op.opType, 'insert');
      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['targetEntityId'], 'murmur-1');
      expect(payload['targetOpId'], 'op-target-1');
      expect(payload['visibility'], 'public');
      expect((payload['sources'] as List), hasLength(1));
    });

    test('update keeps the target tuple and delete emits a tombstone', () {
      final update = CrdtOpBuilder.updateContextNote(
        authorDid: 'did:key:alice',
        entityId: 'context-note-1',
        targetEntityType: 'murmur',
        targetEntityId: 'murmur-1',
        targetOpId: 'op-target-1',
        targetContentHash: 'sha256:${List.filled(64, 'b').join()}',
        body: 'Revised context',
        sources: const [
          {'url': 'https://example.test/revised'},
        ],
      );
      expect(update.opType, 'update');
      expect(
        CrdtOpBuilder.decodePayload(update.payload)['targetContentHash'],
        'sha256:${List.filled(64, 'b').join()}',
      );

      final deletion = CrdtOpBuilder.deleteContextNote(
        authorDid: 'did:key:alice',
        entityId: 'context-note-1',
      );
      expect(deletion.opType, 'delete');
      expect(
        CrdtOpBuilder.decodePayload(deletion.payload).containsKey('deletedAt'),
        isTrue,
      );
    });
  });

  group('CrdtOpBuilder follow', () {
    test('createFollow builds a federated follow op keyed by target DID', () {
      final op = CrdtOpBuilder.createFollow(
        followerDid: 'did:key:reader',
        targetDid: 'did:key:author',
      );

      expect(op.entityType, 'follow');
      expect(op.opType, 'insert');
      // author_did is the follower; entityId is the stable edge (target DID).
      expect(op.authorDid, 'did:key:reader');
      expect(op.entityId, 'did:key:author');

      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['targetDid'], 'did:key:author');
      expect(payload['visibility'], 'federated');
      expect(payload['state'], 'requested');
    });

    test('createFollowGrant builds a target-authored relationship VC', () {
      final op = CrdtOpBuilder.createFollowGrant(
        targetDid: 'did:key:author',
        followerDid: 'did:key:reader',
        requestOpId: 'request-1',
        accepted: true,
      );
      final payload = CrdtOpBuilder.decodePayload(op.payload);
      final credential = payload['credential'] as Map<String, dynamic>;
      final subject = credential['credentialSubject'] as Map<String, dynamic>;

      expect(op.entityType, 'follow_grant');
      expect(op.authorDid, 'did:key:author');
      expect(op.entityId, 'did:key:reader');
      expect(payload['requestOpId'], 'request-1');
      expect(credential['issuer'], 'did:key:author');
      expect(credential['type'], [
        'VerifiableCredential',
        'FollowGrantCredential',
      ]);
      expect(subject['id'], 'did:key:reader');
      expect(subject['relationship'], 'approved_follower');
    });

    test('deleteFollow retracts the same edge', () {
      final op = CrdtOpBuilder.deleteFollow(
        followerDid: 'did:key:reader',
        targetDid: 'did:key:author',
      );

      expect(op.entityType, 'follow');
      expect(op.opType, 'delete');
      expect(op.authorDid, 'did:key:reader');
      expect(op.entityId, 'did:key:author');
      expect(
        CrdtOpBuilder.decodePayload(op.payload)['targetDid'],
        'did:key:author',
      );
    });
  });

  group('CrdtOpBuilder schema version (Phase 0 — API versioning)', () {
    test('builders stamp opSchemaVersion 1 on every authored op', () {
      expect(CrdtOpBuilder.opSchemaVersion, 1);

      final ops = [
        CrdtOpBuilder.createPost(
          authorDid: 'did:key:alice',
          entityId: 'post-1',
          boardId: 'board-1',
          threadId: 'thread-1',
          content: 'hello',
        ),
        CrdtOpBuilder.createMurmur(
          authorDid: 'did:key:alice',
          entityId: 'murmur-1',
          text: 'hi',
        ),
        CrdtOpBuilder.updatePost(
          authorDid: 'did:key:alice',
          entityId: 'post-1',
          newContent: 'edited',
        ),
        CrdtOpBuilder.deletePost(authorDid: 'did:key:alice', entityId: 'p1'),
        CrdtOpBuilder.updateThread(
          authorDid: 'did:key:alice',
          entityId: 'thread-1',
          newTitle: 'Edited title',
        ),
        CrdtOpBuilder.deleteThread(
          authorDid: 'did:key:alice',
          entityId: 'thread-1',
        ),
      ];

      for (final op in ops) {
        expect(op.schemaVersion, CrdtOpBuilder.opSchemaVersion);
      }
    });

    test('thread mutations use update/delete schema operations', () {
      final update = CrdtOpBuilder.updateThread(
        authorDid: 'did:key:alice',
        entityId: 'thread-1',
        newTitle: 'Edited title',
      );
      final deletion = CrdtOpBuilder.deleteThread(
        authorDid: 'did:key:alice',
        entityId: 'thread-1',
      );

      expect(update.entityType, 'thread');
      expect(update.opType, 'update');
      expect(
        CrdtOpBuilder.decodePayload(update.payload)['title'],
        'Edited title',
      );
      expect(deletion.entityType, 'thread');
      expect(deletion.opType, 'delete');
      expect(
        CrdtOpBuilder.decodePayload(deletion.payload).containsKey('deletedAt'),
        isTrue,
      );
    });

    test('OpsQueueEntry JSON round-trips schemaVersion and defaults to 1', () {
      final op = CrdtOpBuilder.createMurmur(
        authorDid: 'did:key:alice',
        entityId: 'murmur-1',
        text: 'hi',
      );

      final restored = OpsQueueEntry.fromJson(op.toJson());
      expect(restored.schemaVersion, 1);

      // Entries persisted before the field existed deserialize as version 1.
      final legacyJson = op.toJson()..remove('schemaVersion');
      expect(OpsQueueEntry.fromJson(legacyJson).schemaVersion, 1);
    });
  });

  group('CrdtOpBuilder profile', () {
    test('createProfile builds a public profile op keyed by author DID', () {
      final op = CrdtOpBuilder.createProfile(
        authorDid: 'did:key:alice',
        handle: 'alice.example',
        displayName: 'Alice',
        bio: 'hello',
        credentialTypes: const ['AgeOver18Credential', 'NationalityCredential'],
      );

      expect(op.entityType, 'profile');
      expect(op.opType, 'insert');
      expect(op.authorDid, 'did:key:alice');
      expect(op.entityId, 'did:key:alice');

      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['handle'], 'alice.example');
      expect(payload['displayName'], 'Alice');
      expect(payload['bio'], 'hello');
      expect(payload['visibility'], 'public');
      expect(payload['credentialTypes'], [
        'AgeOver18Credential',
        'NationalityCredential',
      ]);
    });
  });
}
