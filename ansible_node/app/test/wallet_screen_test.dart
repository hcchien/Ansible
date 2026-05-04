import 'package:ansible_node/screens/wallet_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wallet screen lists credential status and expiry', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository.withCredentials([
      WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.trisaura.io',
        holderDid: 'did:key:z6Mkholder',
        credentialType: 'TrisAuraHumanityCredential',
        status: WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 4),
        validUntil: DateTime.utc(2026, 8, 2),
        displayName: 'Verified Human',
        createdAt: DateTime.utc(2026, 5, 4, 10),
        updatedAt: DateTime.utc(2026, 5, 4, 10),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(home: WalletScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Verified Human'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Expires 2026-08-02'), findsOneWidget);
  });

  testWidgets('wallet screen shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: WalletScreen(repository: InMemoryWalletRepository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('No credentials yet'), findsOneWidget);
    expect(find.text('Add credential'), findsOneWidget);
  });
}
