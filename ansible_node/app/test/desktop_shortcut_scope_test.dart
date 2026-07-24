import 'package:ansible_node/services/platform_capabilities.dart';
import 'package:ansible_node/widgets/desktop_shortcut_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop shortcuts trigger compose and refresh', (tester) async {
    var compose = 0;
    var refresh = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopShortcutScope(
          capabilities: PlatformCapabilities.forPlatform(ElixPlatform.macos),
          onCompose: () => compose += 1,
          onRefresh: () => refresh += 1,
          child: const Scaffold(body: Text('desktop')),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(compose, 1);
    expect(refresh, 1);
  });

  testWidgets('mobile keeps the child without desktop shortcut capture', (
    tester,
  ) async {
    var compose = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopShortcutScope(
          capabilities: PlatformCapabilities.forPlatform(ElixPlatform.ios),
          onCompose: () => compose += 1,
          onRefresh: () {},
          child: const Scaffold(body: Text('mobile')),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(compose, 0);
  });
}
