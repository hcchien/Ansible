import 'package:ansible_node/screens/edit_profile_screen.dart';
import 'package:ansible_node/screens/sync_settings_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'ansible_canonical_did': 'did:elix:testidentity',
      'ansible_canonical_handle': 'canonical.elix.cool',
      'ansible_canonical_public_key': 'test-key',
    });
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets(
    'preview uses edited nickname and save opens publication guidance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(db: db, did: 'did:elix:testidentity'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'My public nickname',
      );
      await tester.ensureVisible(
        find.byKey(const Key('public_profile_preview')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('public_profile_preview')),
          matching: find.text('My public nickname'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('同意並前往發布'));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '同意並前往發布'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('public_profile_consent')),
      );
      await tester.tap(find.byKey(const Key('public_profile_consent')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('同意並前往發布'));
      await tester.tap(find.text('同意並前往發布'));
      await tester.pumpAndSettle();
      expect(
        await DriftContactRepository(db).contactForDid('did:elix:testidentity'),
        isNull,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        await DriftContactRepository(db).contactForDid('did:elix:testidentity'),
        isNull,
      );
      await tester.tap(find.text('同意並前往發布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認並繼續'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SyncSettingsScreen>(find.byType(SyncSettingsScreen))
            .profilePublication,
        isTrue,
      );
      expect(find.text('檔案已儲存，下一步是發布'), findsOneWidget);
      expect(find.text('已可被搜尋'), findsNothing);
      expect(
        (await DriftContactRepository(
          db,
        ).contactForDid('did:elix:testidentity'))?.displayName,
        'My public nickname',
      );
    },
  );

  testWidgets('onboarding can be skipped without creating a public contact', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditProfileScreen(
                    db: db,
                    did: 'did:elix:testidentity',
                    isOnboarding: true,
                  ),
                ),
              ),
              child: const Text('Start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暫時不要'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(
      await DriftContactRepository(db).contactForDid('did:elix:testidentity'),
      isNull,
    );
  });

  testWidgets('canonical handle is visible but cannot be edited as profile', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 23);
    await DriftContactRepository(db).upsertContact(
      ContactRecord(
        subjectDid: 'did:elix:testidentity',
        handle: 'accidentally-edited.elix.cool',
        source: 'self',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EditProfileScreen(db: db, did: 'did:elix:testidentity'),
      ),
    );
    await tester.pumpAndSettle();

    final handleField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'canonical.elix.cool'),
    );
    expect(handleField.readOnly, isTrue);
    expect(handleField.controller!.text, 'canonical.elix.cool');
    expect(find.textContaining('Handle 與你的 DID 身分綁定'), findsOneWidget);
    expect(
      (await DriftContactRepository(
        db,
      ).contactForDid('did:elix:testidentity'))?.handle,
      'canonical.elix.cool',
    );
  });

  testWidgets('legacy identity without a canonical handle can still set one', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final now = DateTime.utc(2026, 8, 23);
    await DriftContactRepository(db).upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:legacy',
        source: 'self',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EditProfileScreen(db: db, did: 'did:plc:legacy'),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[1].readOnly, isFalse);
    expect(find.textContaining('Handle 與你的 DID 身分綁定'), findsNothing);
  });
}
