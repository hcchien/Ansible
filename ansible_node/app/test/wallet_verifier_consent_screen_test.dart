import 'dart:convert';

import 'package:ansible_node/screens/wallet_verifier_consent_screen.dart';
import 'package:ansible_node/services/oid4vp_presentation_service.dart';
import 'package:ansible_node/services/oid4vp_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows verifier request disclosure before submitting VP', (
    tester,
  ) async {
    final service = _FakeOid4vpPresentationService();

    await tester.pumpWidget(
      MaterialApp(
        home: WalletVerifierConsentScreen(
          holderDid: 'did:key:z6Mkholder',
          request: Oid4vpAuthorizationRequest.parse(_requestUri()),
          presentationService: service,
          now: () => DateTime.utc(2026, 5, 30, 10),
        ),
      ),
    );

    expect(find.text('Verifier Request'), findsWidgets);
    expect(find.text('https://verifier.example'), findsOneWidget);
    expect(find.text('TrisAuraHumanityCredential'), findsOneWidget);
    expect(find.textContaining('humanVerified'), findsOneWidget);
    expect(find.textContaining('身分證字號'), findsOneWidget);
    expect(find.textContaining('MobileMoica response'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意並送出 VP'));
    await tester.pump();
    await tester.pump();

    expect(service.approvedWithHolderDid, 'did:key:z6Mkholder');
    expect(service.approvedAt, DateTime.utc(2026, 5, 30, 10));
    expect(find.text('VP 已送出'), findsOneWidget);
  });
}

String _requestUri() {
  final definition = {
    'id': 'pd-humanity',
    'input_descriptors': [
      {
        'id': 'humanity-vc',
        'constraints': {
          'fields': [
            {
              'path': [r'$.type'],
              'filter': {
                'type': 'array',
                'contains': {'const': 'TrisAuraHumanityCredential'},
              },
            },
            {
              'path': [r'$.credentialSubject.humanVerified'],
            },
          ],
        },
      },
    ],
  };
  return Uri(
    scheme: 'openid4vp',
    host: 'authorize',
    queryParameters: {
      'client_id': 'https://verifier.example',
      'response_type': 'vp_token',
      'response_mode': 'direct_post',
      'response_uri': 'https://verifier.example/direct_post',
      'nonce': 'nonce-123',
      'presentation_definition': jsonEncode(definition),
    },
  ).toString();
}

class _FakeOid4vpPresentationService implements Oid4vpPresentationApprover {
  String? approvedWithHolderDid;
  DateTime? approvedAt;

  @override
  Future<Oid4vpSubmissionResult> approve({
    required String holderDid,
    required Oid4vpAuthorizationRequest request,
    required DateTime now,
  }) async {
    approvedWithHolderDid = holderDid;
    approvedAt = now;
    return const Oid4vpSubmissionResult(
      credentialId: 'urn:uuid:test-humanity',
      verifierAudience: 'https://verifier.example',
    );
  }
}
