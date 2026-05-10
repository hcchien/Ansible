import 'package:ansible_node/services/forum_publication_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createThread requires one primary hosted board target', () async {
    final hostedBoards = InMemoryHostedBoardRepository();
    final now = DateTime.utc(2026, 5, 10);
    await _seedSubscription(hostedBoards, now, subscriptionId: 'primary');

    final result = await ForumPublicationService(
      hostedBoards: hostedBoards,
      now: () => now,
    ).createThread(localDraftId: 'draft-1', primaryTargetId: 'primary');

    final targets = await hostedBoards.listPublicationTargets();
    expect(result.accepted, 1);
    expect(targets.single.localSourceId, 'draft-1');
    expect(targets.single.sourceType, BoardPublicationSourceType.threadDraft);
    expect(targets.single.mode, BoardPublicationMode.primary);
    expect(targets.single.status, BoardPublicationStatus.pending);
  });

  test(
    'cross-post targets create independent publication target rows',
    () async {
      final hostedBoards = InMemoryHostedBoardRepository();
      final now = DateTime.utc(2026, 5, 10);
      await _seedSubscription(hostedBoards, now, subscriptionId: 'primary');
      await _seedSubscription(
        hostedBoards,
        now,
        subscriptionId: 'cross',
        forumHostId: 'host-2',
        hostedBoardId: 'hosted-news',
        localBoardId: 'local-news',
      );

      final result =
          await ForumPublicationService(
            hostedBoards: hostedBoards,
            now: () => now,
          ).createThread(
            localDraftId: 'draft-1',
            primaryTargetId: 'primary',
            crossPostTargetIds: const ['cross'],
          );

      final targets = await hostedBoards.listPublicationTargets();
      expect(result.accepted, 2);
      expect(targets.map((target) => target.mode), [
        BoardPublicationMode.crossPost,
        BoardPublicationMode.primary,
      ]);
      expect(targets.map((target) => target.forumHostId).toSet(), {
        'host-1',
        'host-2',
      });
    },
  );

  test(
    'public content item projection keeps content local canonical',
    () async {
      final hostedBoards = InMemoryHostedBoardRepository();
      final contentItems = InMemoryContentItemRepository();
      final now = DateTime.utc(2026, 5, 10);
      await _seedSubscription(hostedBoards, now, subscriptionId: 'target');
      await contentItems.create(
        ContentItem(
          id: 'note-1',
          authorDid: 'did:key:z6MkUser',
          mode: ContentMode.note,
          title: 'Public note',
          body: 'Body',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          localOnly: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result =
          await ForumPublicationService(
            hostedBoards: hostedBoards,
            contentItems: contentItems,
            now: () => now,
          ).projectContentItem(
            contentItemId: 'note-1',
            targetIds: const ['target'],
          );

      final targets = await hostedBoards.listPublicationTargets();
      expect(result.accepted, 1);
      expect((await contentItems.getById('note-1'))!.id, 'note-1');
      expect(targets.single.localSourceId, 'note-1');
      expect(targets.single.sourceType, BoardPublicationSourceType.contentItem);
      expect(targets.single.mode, BoardPublicationMode.projection);
    },
  );

  test('private content item cannot be projected to forum boards', () async {
    final hostedBoards = InMemoryHostedBoardRepository();
    final contentItems = InMemoryContentItemRepository();
    final now = DateTime.utc(2026, 5, 10);
    await _seedSubscription(hostedBoards, now, subscriptionId: 'target');
    await contentItems.create(
      ContentItem(
        id: 'note-1',
        authorDid: 'did:key:z6MkUser',
        mode: ContentMode.note,
        title: 'Private note',
        body: 'Body',
        status: ContentStatus.active,
        visibility: ContentVisibility.private,
        localOnly: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final result = await ForumPublicationService(
      hostedBoards: hostedBoards,
      contentItems: contentItems,
      now: () => now,
    ).projectContentItem(contentItemId: 'note-1', targetIds: const ['target']);

    expect(result.accepted, 0);
    expect(result.rejected, 1);
    expect(result.errors.single, 'private_content_not_projectable');
    expect(await hostedBoards.listPublicationTargets(), isEmpty);
  });
}

Future<void> _seedSubscription(
  InMemoryHostedBoardRepository hostedBoards,
  DateTime now, {
  required String subscriptionId,
  String forumHostId = 'host-1',
  String hostedBoardId = 'hosted-general',
  String localBoardId = 'local-general',
}) async {
  await hostedBoards.upsertSubscription(
    BoardSubscription(
      subscriptionId: subscriptionId,
      forumHostId: forumHostId,
      hostedBoardId: hostedBoardId,
      localBoardId: localBoardId,
      readEnabled: true,
      writeEnabled: true,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
