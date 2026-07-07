import 'package:ansible_node/screens/wallet_verifier_scanner_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  testWidgets('opens web session approval when scanning login QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletVerifierScannerScreen(
          holderDid: 'did:plc:abc23456789',
          walletRepository: InMemoryWalletRepository(),
          allowLocalHttp: false,
          allowedWebSessionRelayOrigins: const {'https://relay.elix.cool'},
          scannerBuilder: (context, onDetect) {
            return Center(
              child: ElevatedButton(
                key: const Key('scan_web_session_qr'),
                onPressed: () {
                  onDetect(
                    const BarcodeCapture(
                      barcodes: [
                        Barcode(
                          rawValue:
                              'trisaura://web-session/approve?challenge_id=wsc_abc&relay_origin=https%3A%2F%2Frelay.elix.cool',
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('scan'),
              ),
            );
          },
          webSessionApprovalBuilder: (context, link) {
            return Scaffold(
              body: Text('${link.challengeId} ${link.relayOrigin}'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('scan_web_session_qr')));
    await tester.pumpAndSettle();

    expect(find.text('wsc_abc https://relay.elix.cool'), findsOneWidget);
  });

  testWidgets('rejects web session QR from an untrusted relay origin', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletVerifierScannerScreen(
          holderDid: 'did:plc:abc23456789',
          walletRepository: InMemoryWalletRepository(),
          allowLocalHttp: false,
          allowedWebSessionRelayOrigins: const {'https://relay.elix.cool'},
          scannerBuilder: (context, onDetect) {
            return Center(
              child: ElevatedButton(
                key: const Key('scan_untrusted_web_session_qr'),
                onPressed: () {
                  onDetect(
                    const BarcodeCapture(
                      barcodes: [
                        Barcode(
                          rawValue:
                              'trisaura://web-session/approve?challenge_id=wsc_bad&relay_origin=https%3A%2F%2Fevil.example',
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('scan'),
              ),
            );
          },
          webSessionApprovalBuilder: (context, link) {
            return Scaffold(body: Text(link.challengeId));
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('scan_untrusted_web_session_qr')));
    await tester.pumpAndSettle();

    expect(find.text('wsc_bad'), findsNothing);
    expect(find.text('無法解析這個 QR request。'), findsOneWidget);
  });
}
