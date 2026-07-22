import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'issuer administration is hidden in an advanced fold by default',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsHomeScreen(db: db, did: 'did:elix:settings-test'),
        ),
      );
      await tester.pump();

      final fold = find.byKey(const Key('settings_issuer_tools_fold'));
      await tester.dragUntilVisible(
        fold,
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(fold, findsOneWidget);
      expect(find.byKey(const Key('settings_hosted_issuer_row')), findsNothing);
      expect(
        find.byKey(const Key('settings_hosted_issuer_admins_row')),
        findsNothing,
      );

      await tester.tap(fold);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings_hosted_issuer_row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_hosted_issuer_admins_row')),
        findsOneWidget,
      );
    },
  );
}
