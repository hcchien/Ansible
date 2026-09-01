import 'dart:async';

import 'package:ansible_node/l10n/app_localizations.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/widgets/global_sync_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(ElixGlobalSyncController controller, {VoidCallback? unavailable}) {
    return MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: ElixGlobalSyncShortcutRow(
          controller: controller,
          onUnavailable: unavailable,
        ),
      ),
    );
  }

  testWidgets('matches the compact handoff sync treatment', (tester) async {
    final controller = ElixGlobalSyncController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));

    expect(find.byKey(const Key('global_sync_shortcut')), findsOneWidget);
    expect(find.text('同步'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('global_sync_shortcut'))).height,
      28,
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const Key('global_sync_shortcut')),
            matching: find.byType(Material),
          )
          .last,
    );
    expect(material.color, AnsibleDesign.ochre);
    expect(material.borderRadius, BorderRadius.circular(999));
  });

  testWidgets('runs the attached sync action once and shows progress', (
    tester,
  ) async {
    final controller = ElixGlobalSyncController();
    addTearDown(controller.dispose);
    final completer = Completer<void>();
    var calls = 0;
    controller.attach(() {
      calls += 1;
      return completer.future;
    });
    await tester.pumpWidget(app(controller));

    await tester.tap(find.byKey(const Key('global_sync_shortcut_button')));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byKey(const Key('global_sync_shortcut_button')));
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('reports that sync is unavailable before identity setup', (
    tester,
  ) async {
    final controller = ElixGlobalSyncController();
    addTearDown(controller.dispose);
    var unavailableCalls = 0;
    await tester.pumpWidget(
      app(controller, unavailable: () => unavailableCalls += 1),
    );

    await tester.tap(find.byKey(const Key('global_sync_shortcut_button')));
    await tester.pump();
    expect(unavailableCalls, 1);
  });
}
