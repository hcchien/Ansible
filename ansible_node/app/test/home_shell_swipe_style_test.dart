import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home shell pages can be changed by horizontal swipe', (
    tester,
  ) async {
    await _pumpHomeShell(tester);

    expect(find.byKey(const Key('home_swipe_page_view')), findsOneWidget);
    expect(_tabLabelColor(tester, 'feed'), AnsibleDesign.ink);

    await tester.drag(
      find.byKey(const Key('home_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(_tabLabelColor(tester, 'circle'), AnsibleDesign.ink);
  });

  testWidgets('screen styles are configured independently per main screen', (
    tester,
  ) async {
    await _pumpHomeShell(tester);

    await tester.tap(find.byKey(const Key('screen_style_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screen_style_choice_vellum')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paperElev);

    await tester.drag(
      find.byKey(const Key('home_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);

    await tester.tap(find.byKey(const Key('screen_style_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screen_style_choice_deep')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paperDeep);

    await tester.drag(
      find.byKey(const Key('home_swipe_page_view')),
      const Offset(340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paperElev);
  });
}

Future<void> _pumpHomeShell(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() => db.close());

  await tester.pumpWidget(
    MyApp(
      db: db,
      didManager: _EmptyDidManager(),
      didPlcManager: _ExistingDidPlcManager(),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(HomeShell), findsOneWidget);
}

Color? _tabLabelColor(WidgetTester tester, String tabName) {
  final label = tester.widget<Text>(find.byKey(Key('home_tab_label_$tabName')));
  return label.style?.color;
}

Color? _screenStyleColor(WidgetTester tester, String screenName) {
  final box = tester.widget<AnimatedContainer>(
    find.byKey(Key('screen_style_scope_$screenName')),
  );
  final decoration = box.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

class _EmptyDidManager implements DidManager {
  @override
  Future<OwnedDid> generate() {
    throw UnimplementedError('Not used by this test.');
  }

  @override
  Future<OwnedDid?> load() async => null;

  @override
  Future<void> delete() async {}
}

class _ExistingDidPlcManager implements DidPlcManager {
  @override
  Future<DidPlcResult> createDid({
    required String handle,
    String pdsEndpoint = 'https://trisaura.io',
    String? signingKeyHex,
  }) {
    throw UnimplementedError('Not used by this test.');
  }

  @override
  Future<void> deleteDid() async {}

  @override
  Future<DidPlcResult?> loadDid() async => const DidPlcResult(
    did: 'did:plc:abcdefghijklmnop',
    genesisJson: '{"type":"plc_genesis"}',
    publicKeyHex: 'ab',
  );
}
