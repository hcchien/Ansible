import 'package:ansible_node/widgets/remote_node_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    void Function(Map<String, String?>?) result, {
    String? initialUrl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result(
                await showDialog<Map<String, String?>>(
                  context: context,
                  builder: (_) => RemoteNodeFormDialog(initialUrl: initialUrl),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('blank URL visibly defaults to production only when saved', (
    tester,
  ) async {
    Map<String, String?>? result;
    await open(tester, (value) => result = value);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('relay_url_field')))
          .controller!
          .text,
      productionRelayUrl,
    );
    expect(result, isNull);
    await tester.enterText(find.byKey(const Key('relay_url_field')), '  ');
    expect(find.textContaining('留空時使用'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(result?['url'], productionRelayUrl);
    expect(result?['name'], 'Elix Relay');
  });
  testWidgets(
    'custom URL remains editable and invalid schemes cannot be saved',
    (tester) async {
      Map<String, String?>? result;
      await open(
        tester,
        (value) => result = value,
        initialUrl: 'https://custom.example',
      );
      expect(find.text('自訂伺服器'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('relay_url_field')),
        'javascript:bad',
      );
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('relay_url_field')),
        'https://custom.example/path/',
      );
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expect(result?['url'], 'https://custom.example/path');
    },
  );
  testWidgets(
    'preset chooser restores production and cancelling writes nothing at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, String?>? result;
      await open(
        tester,
        (value) => result = value,
        initialUrl: 'https://custom.example',
      );
      await tester.tap(find.text('自訂伺服器'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elix 正式伺服器（預設）').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('relay_url_field')))
            .controller!
            .text,
        productionRelayUrl,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
