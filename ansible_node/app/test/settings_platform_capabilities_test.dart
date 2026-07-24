import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/platform_capabilities.dart';
import 'package:ansible_node/widgets/ansible_screen_chrome.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('macOS offers hardware-key upgrade', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsHomeScreen(
          db: db,
          did: 'did:elix:mac',
          platformCapabilities:
              PlatformCapabilities.forPlatform(ElixPlatform.macos),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_identity_custody_row')),
      300,
    );

    final row = tester.widget<AnsibleSettingsRow>(
      find.byKey(const Key('settings_identity_custody_row')),
    );
    expect(row.value, '可升級');
    expect(row.onTap, isNotNull);
    expect(row.sub, contains('裝置硬體'));
  });

  testWidgets('Windows labels software custody as reduced trust', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsHomeScreen(
          db: db,
          did: 'did:elix:windows',
          platformCapabilities:
              PlatformCapabilities.forPlatform(ElixPlatform.windows),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_identity_custody_row')),
      300,
    );

    final row = tester.widget<AnsibleSettingsRow>(
      find.byKey(const Key('settings_identity_custody_row')),
    );
    expect(row.value, '降低信任');
    expect(row.onTap, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_issuer_tools_fold')),
      -200,
    );
    final issuer = tester.widget<AnsibleSettingsRow>(
      find.byKey(const Key('settings_issuer_tools_fold')),
    );
    expect(issuer.onTap, isNull);
    expect(issuer.sub, contains('降低信任'));
  });
}
