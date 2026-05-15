import 'package:ansible_node/screens/contact_picker_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('contact picker returns selected contact DID', (tester) async {
    final contacts = [
      ContactRecord(
        subjectDid: 'did:plc:alice',
        handle: 'alice.elix.app',
        displayName: 'Alice',
        messengerAvailability: MessengerAvailability.available,
        createdAt: DateTime.utc(2026, 5, 14),
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    ];

    String? selectedDid;
    await tester.pumpWidget(
      MaterialApp(
        home: ContactPickerScreen(
          contacts: contacts,
          onContactSelected: (contact) => selectedDid = contact.subjectDid,
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice.elix.app'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    expect(selectedDid, 'did:plc:alice');
  });

  testWidgets('contact picker resolves typed DID into selectable contact', (
    tester,
  ) async {
    String? selectedDid;
    await tester.pumpWidget(
      MaterialApp(
        home: ContactPickerScreen(
          contacts: const [],
          onResolveInput: (input) async {
            return ContactRecord(
              subjectDid: input,
              messengerAvailability: MessengerAvailability.available,
              createdAt: DateTime.utc(2026, 5, 15),
              updatedAt: DateTime.utc(2026, 5, 15),
            );
          },
          onContactSelected: (contact) => selectedDid = contact.subjectDid,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('contact-id-input')),
      'did:plc:bob',
    );
    await tester.tap(find.byTooltip('搜尋 ID'));
    await tester.pumpAndSettle();

    expect(find.text('did:plc:bob'), findsWidgets);
    await tester.tap(find.text('did:plc:bob').last);
    expect(selectedDid, 'did:plc:bob');
  });
}
