import 'package:ansible_node/screens/about_screen.dart';
import 'package:ansible_node/services/external_url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Elix',
      packageName: 'cool.elix.app',
      version: '1.0.0',
      buildNumber: '7',
      buildSignature: '',
      installerStore: null,
    );
  });

  testWidgets('renders app identity, version, and legal rows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(urlLauncher: FakeExternalUrlLauncher())),
    );
    await tester.pumpAndSettle();

    // No localization delegates installed → uiCopy falls back to zh strings.
    expect(find.text('Elix'), findsOneWidget);
    expect(find.text('隱私權政策'), findsOneWidget);
    expect(find.text('服務條款'), findsOneWidget);
    expect(find.text('關於 Elix'), findsOneWidget);
    expect(find.text('刪除帳號與資料'), findsOneWidget);
    expect(find.byKey(const Key('about_version_label')), findsOneWidget);
    expect(find.text('v1.0.0 (7)'), findsOneWidget);
  });

  testWidgets('tapping privacy row launches the forum privacy URL externally', (
    tester,
  ) async {
    final launcher = FakeExternalUrlLauncher();
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(urlLauncher: launcher)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隱私權政策'));
    await tester.pump();

    expect(
      launcher.opened.single.toString(),
      'https://forum.elix.cool/privacy',
    );
  });

  testWidgets('each legal row opens its corresponding page', (tester) async {
    final launcher = FakeExternalUrlLauncher();
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(urlLauncher: launcher)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('服務條款'));
    await tester.tap(find.text('關於 Elix'));
    await tester.ensureVisible(find.text('刪除帳號與資料'));
    await tester.tap(find.text('刪除帳號與資料'));
    await tester.pump();

    expect(launcher.opened.map((uri) => uri.toString()).toList(), [
      'https://forum.elix.cool/terms',
      'https://forum.elix.cool/about',
      'https://forum.elix.cool/account-deletion',
    ]);
  });

  testWidgets('a custom forum web base URL is respected (trailing slash ok)', (
    tester,
  ) async {
    final launcher = FakeExternalUrlLauncher();
    await tester.pumpWidget(
      MaterialApp(
        home: AboutScreen(
          urlLauncher: launcher,
          forumWebBaseUrl: 'https://forum-dev.elix.cool/',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隱私權政策'));
    await tester.pump();

    expect(
      launcher.opened.single.toString(),
      'https://forum-dev.elix.cool/privacy',
    );
  });

  testWidgets('shows a snackbar when the browser cannot be opened', (
    tester,
  ) async {
    final launcher = FakeExternalUrlLauncher(shouldOpen: false);
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(urlLauncher: launcher)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隱私權政策'));
    await tester.pump();

    expect(find.textContaining('無法開啟瀏覽器'), findsOneWidget);
  });
}

class FakeExternalUrlLauncher implements ExternalUrlLauncher {
  FakeExternalUrlLauncher({this.shouldOpen = true});

  final bool shouldOpen;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return shouldOpen;
  }
}
