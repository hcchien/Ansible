import 'dart:convert';
import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/widgets/reaction_bar.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Signer implements DidSigner {
  bool fail = false;
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    if (fail) throw StateError('signing cancelled');
    return Ed25519Signature('test-signature');
  }
}

void main() {
  testWidgets(
    'reply selects switches removes and reselects one signed reaction',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final signer = _Signer();
      final queue = DriftOpsQueueRepository(db);
      final repo = DriftReactionRepository(db);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              db: db,
              targetId: 'reply',
              targetType: TargetType.post,
              localDid: 'did:test:me',
              opsDispatchService: OpsDispatchService(
                repository: queue,
                signer: signer,
              ),
              onFlushPendingOps: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> choose(String emoji) async {
        await tester.tap(find.byType(IconButton).first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, emoji));
        await tester.pumpAndSettle();
      }

      await choose('😄');
      var rows = await repo.listByTarget('post', 'reply');
      expect(rows.single.reactionType, ReactionType.happy);
      final id = rows.single.id;
      await choose('😠');
      rows = await repo.listByTarget('post', 'reply');
      expect(rows.single.id, id);
      expect(rows.single.reactionType, ReactionType.angry);
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('移除我的'));
      await tester.pumpAndSettle();
      expect(await repo.listByTarget('post', 'reply'), isEmpty);
      await choose('😢');
      expect(
        (await repo.listByTarget('post', 'reply')).single.reactionType,
        ReactionType.sad,
      );
      final ops = await queue.listAll();
      expect(ops.map((o) => o.opType).toList(), [
        'insert',
        'update',
        'delete',
        'insert',
      ]);
      for (final op in ops) {
        final payload = jsonDecode(utf8.decode(base64Decode(op.payload)));
        expect(payload['targetType'], 'post');
        expect(payload['targetId'], 'reply');
      }
      signer.fail = true;
      await choose('👍');
      expect(
        (await repo.listByTarget('post', 'reply')).single.reactionType,
        ReactionType.sad,
      );
      expect((await queue.listAll()).length, 4);
      await tester.runAsync(db.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'reopened reply keeps a signed deletion over a stale AppView copy',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final op = CrdtOpBuilder.deleteReaction(
        authorDid: 'did:test:me',
        entityId: 'old',
        targetType: 'post',
        targetId: 'reply',
      );
      await DriftOpsQueueRepository(
        db,
      ).enqueue(op.copyWith(signature: 'signed', status: 'sent'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              db: db,
              targetId: 'reply',
              targetType: TargetType.post,
              localDid: 'did:test:me',
              remoteItems: const [
                AppViewTimelineItem(
                  entityType: 'reaction',
                  entityId: 'old',
                  authorDid: 'did:test:me',
                  payload: {
                    'targetType': 'post',
                    'targetId': 'reply',
                    'reactionType': 'angry',
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('♡'), findsOneWidget);
      await tester.runAsync(db.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('four types fit mobile and expand into attributable groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    final remote = [
      for (final type in ReactionType.values)
        AppViewTimelineItem(
          entityType: 'reaction',
          entityId: type.name,
          authorDid: 'did:test:${type.name}',
          payload: {
            'targetType': 'post',
            'targetId': 'reply',
            'reactionType': type.name,
          },
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ReactionBar(
                db: db,
                targetId: 'reply',
                targetType: TargetType.post,
                remoteItems: remote,
              ),
              const SizedBox(width: 22),
              const Icon(Icons.comment),
              const SizedBox(width: 22),
              const Icon(Icons.repeat),
              const Spacer(),
              const Icon(Icons.share),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    for (final type in ReactionType.values) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('reaction_person_did:test:${type.name}')),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.byKey(ValueKey('reaction_person_did:test:${type.name}')),
        findsOneWidget,
      );
    }
    await tester.runAsync(db.close);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
