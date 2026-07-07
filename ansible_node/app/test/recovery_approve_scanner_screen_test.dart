import 'package:ansible_node/screens/recovery_approve_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  testWidgets('opens web session approval when scanning a login QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecoveryApproveScannerScreen(
          localDid: 'did:plc:abc23456789',
          allowLocalHttp: false,
          allowedWebSessionRelayOrigins: const {'https://relay-dev.elix.cool'},
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
                              'trisaura://web-session/approve?challenge_id=wsc_abc&relay_origin=https%3A%2F%2Frelay-dev.elix.cool',
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

    expect(find.text('wsc_abc https://relay-dev.elix.cool'), findsOneWidget);
  });

  testWidgets('returns to settings after approving web login QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: const Text('Settings page'),
            floatingActionButton: ElevatedButton(
              key: const Key('open_recovery_scanner'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecoveryApproveScannerScreen(
                      localDid: 'did:plc:abc23456789',
                      allowLocalHttp: false,
                      allowedWebSessionRelayOrigins: const {
                        'https://relay-dev.elix.cool',
                      },
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
                                          'trisaura://web-session/approve?challenge_id=wsc_abc&relay_origin=https%3A%2F%2Frelay-dev.elix.cool',
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Text('scan'),
                          ),
                        );
                      },
                      webSessionApprovalBuilder: (context, link) {
                        return Scaffold(
                          body: ElevatedButton(
                            key: const Key('approve_web_session'),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text('${link.challengeId} approve'),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_recovery_scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan_web_session_qr')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve_web_session')));
    await tester.pumpAndSettle();

    expect(find.text('Settings page'), findsOneWidget);
    expect(find.byKey(const Key('scan_web_session_qr')), findsNothing);
    expect(find.byKey(const Key('approve_web_session')), findsNothing);
  });
}
