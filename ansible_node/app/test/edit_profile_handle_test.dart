import 'package:ansible_node/screens/edit_profile_screen.dart';
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
}
