import 'package:ansible_node/screens/recovery_guide_screen.dart';
import 'package:ansible_node/screens/sending_center_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'sending center shows local content and cannot cancel an attempted op',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final queue = DriftOpsQueueRepository(db);
      final op = CrdtOpBuilder.createMurmur(
        authorDid: 'did:a',
        entityId: 'sent-item',
        text: '需要重試的內容',
        visibility: 'public',
      );
      await queue.enqueue(
        op.copyWith(status: 'blocked', sentAt: DateTime.now()),
      );
      await DriftContentItemRepository(db).create(
        ContentItem(
          id: 'local-item',
          authorDid: 'did:a',
          mode: ContentMode.murmur,
          body: '只有本機這份',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final retried = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SendingCenterScreen(
            did: 'did:a',
            db: db,
            repository: queue,
            onSync: () async {},
            onRetry: (entry) async {
              retried.add(entry.opId);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('只有本機這份'), findsOneWidget);
      expect(find.text('停止傳送'), findsNothing);
      await tester.ensureVisible(find.text('重試這一項'));
      await tester.tap(find.text('重試這一項'));
      await tester.pumpAndSettle();
      expect(retried, [op.opId]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'recovery guide separates device loss and browser authorization at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: RecoveryGuideScreen(did: 'did:a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('舊手機遺失了'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('貼文、草稿與私密資料會一起回來嗎？'), 250);
      expect(find.textContaining('身分復原不等於資料備份'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
