import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ansible_node/services/issuer_readiness_probe.dart';
import 'package:ansible_node/widgets/posting_gate_notice.dart';

void main() {
  IssuerReadinessProbe probeWith({required bool ready}) {
    return IssuerReadinessProbe(
      issuerBaseUrl: 'https://issuer.test',
      client: MockClient((request) async {
        expect(request.url.path, '/readyz');
        return http.Response(ready ? 'ok' : 'not ready', ready ? 200 : 503);
      }),
    );
  }

  Future<void> pumpNotice(
    WidgetTester tester,
    IssuerReadinessProbe probe,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostingGateNotice(
            localDid: 'did:elix:test',
            issuerProbe: probe,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ready issuer → live upgrade CTA', (tester) async {
    await pumpNotice(tester, probeWith(ready: true));
    expect(find.byKey(const Key('posting_gate_upgrade')), findsOneWidget);
    expect(find.text('升級驗證'), findsOneWidget);
    expect(find.byKey(const Key('posting_gate_coming_soon')), findsNothing);
  });

  testWidgets('fail-closed issuer → 即將開放 interim state, disabled',
      (tester) async {
    await pumpNotice(tester, probeWith(ready: false));
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('posting_gate_coming_soon')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('真人驗證即將開放'), findsOneWidget);
    expect(find.byKey(const Key('posting_gate_upgrade')), findsNothing);
  });

  testWidgets('unreachable issuer → interim state (never a dead-end wizard)',
      (tester) async {
    final probe = IssuerReadinessProbe(
      issuerBaseUrl: 'https://issuer.test',
      client: MockClient((_) async => throw Exception('down')),
    );
    await pumpNotice(tester, probe);
    expect(find.text('真人驗證即將開放'), findsOneWidget);
  });
}
