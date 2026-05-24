import 'package:ansible_node/screens/add_credential_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders credential wizard flow options', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          onCredentialAdded: (_) {},
        ),
      ),
    );

    expect(find.text('TW 身份驗證'), findsOneWidget);
    expect(find.text('Email OTP / Legacy'), findsOneWidget);
  });

  testWidgets('choosing Email starts the legacy OTP flow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          onCredentialAdded: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Email OTP / Legacy'));
    await tester.pumpAndSettle();

    expect(find.text('Email 聯絡方式驗證'), findsOneWidget);
    expect(find.text('發送驗證碼'), findsOneWidget);
  });
}
