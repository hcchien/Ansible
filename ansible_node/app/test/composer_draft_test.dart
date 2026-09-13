import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ansible_node/services/composer_draft_store.dart';
import 'package:ansible_node/screens/post_composer_screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'drafts survive a new store and isolate identity, kind and destination',
    () async {
      final key = ComposerDraftStore.key('did:a', 'poll', 'board1');
      final value = {
        'title': 'Draft',
        'content': 'private text',
        'options': ['A', 'B'],
        'duration': 7,
        'crossPosts': ['board2'],
      };
      await ComposerDraftStore().write(key, value);
      expect(await ComposerDraftStore().read(key), value);
      expect(
        await ComposerDraftStore().read(
          ComposerDraftStore.key('did:b', 'poll', 'board1'),
        ),
        isNull,
      );
      expect(
        await ComposerDraftStore().read(
          ComposerDraftStore.key('did:a', 'reply', 'board1'),
        ),
        isNull,
      );
      expect(
        await ComposerDraftStore().read(
          ComposerDraftStore.key('did:a', 'poll', 'board2'),
        ),
        isNull,
      );
      await ComposerDraftStore().clear(key);
      expect(await ComposerDraftStore().read(key), isNull);
    },
  );

  testWidgets(
    'leaving and reopening restores explicit mention identities without publishing',
    (tester) async {
      final key = ComposerDraftStore.key('did:a', 'reply', 'thread:1');
      await ComposerDraftStore.shared.write(key, {
        'body': 'hello @Alice',
        'mentions': {'did:alice': '@Alice'},
      });
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      );
      final result = nav.currentState!.push<PostComposerResult>(
        MaterialPageRoute(
          builder: (_) => const PostComposerScreen(
            authorDid: 'did:a',
            draftTarget: 'thread:1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('繼續上次的草稿？'), findsOneWidget);
      await tester.tap(find.text('繼續編輯'));
      await tester.pumpAndSettle();
      expect(find.text('hello @Alice'), findsOneWidget);
      await tester.tap(find.byKey(const Key('post_composer_done_button')));
      await tester.pumpAndSettle();
      final submitted = await result;
      expect(submitted!.mentionDids, ['did:alice']);
      // Returning from the editor is not a database commit.
      expect(await ComposerDraftStore.shared.read(key), isNotNull);
      await ComposerDraftStore.shared.clear(submitted.draftKey!);
      expect(await ComposerDraftStore.shared.read(key), isNull);
    },
  );

  testWidgets(
    'back saves edits before returning even inside the debounce window',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const PostComposerScreen(
            authorDid: 'did:a',
            draftTarget: 'thread:2',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('post_composer_body_field')),
        'unfinished',
      );
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        await ComposerDraftStore.shared.read(
          ComposerDraftStore.key('did:a', 'reply', 'thread:2'),
        ),
        containsPair('body', 'unfinished'),
      );
    },
  );
}
