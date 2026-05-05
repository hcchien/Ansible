import 'package:ansible_node/screens/credential_issuance_wizard.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows TW provider and email OTP flow options', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(holderDid: 'did:plc:abcdefghijklmnop'),
        ),
      ),
    );

    expect(find.text('TW 身份驗證'), findsOneWidget);
    expect(find.text('Email OTP / Legacy'), findsOneWidget);
  });

  testWidgets('selecting TW provider shows provider flow panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(
            holderDid: 'did:plc:abcdefghijklmnop',
            walletRepository: InMemoryWalletRepository(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('TW 身份驗證'));
    await tester.pumpAndSettle();

    expect(find.text('開始驗證'), findsOneWidget);
  });

  testWidgets('selecting email shows email OTP panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(
            holderDid: 'did:plc:abcdefghijklmnop',
            walletRepository: InMemoryWalletRepository(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Email OTP / Legacy'));
    await tester.pumpAndSettle();

    expect(find.text('Email 身份驗證'), findsOneWidget);
  });
}
