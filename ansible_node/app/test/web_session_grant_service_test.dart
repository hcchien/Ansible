import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/web_session_grant_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds canonical web session grant payload', () {
    final grant = WebSessionGrant(
      challengeId: 'wsc_test',
      relayOrigin: 'https://relay.trisaura.io',
      webOrigin: 'https://trisaura.io',
      subjectDid: 'did:plc:abc23456789',
      approvingDeviceId: 'app_device_abc',
      scopes: const ['forum:post', 'forum:read'],
      expiresAt: DateTime.utc(2026, 5, 11, 13),
      createdAt: DateTime.utc(2026, 5, 11, 12, 45),
    );

    expect(
      grant.canonicalJson(),
      '{"approving_device_id":"app_device_abc","challenge_id":"wsc_test","created_at":"2026-05-11T12:45:00.000Z","expires_at":"2026-05-11T13:00:00.000Z","relay_origin":"https://relay.trisaura.io","scopes":["forum:post","forum:read"],"subject_did":"did:plc:abc23456789","type":"io.trisaura.webSessionGrant","version":1,"web_origin":"https://trisaura.io"}',
    );
  });

  test('signs canonical grant bytes with the injected DID signer', () async {
    final signer = _RecordingDidSigner();
    final service = WebSessionGrantService(signer: signer);
    final grant = WebSessionGrant(
      challengeId: 'wsc_test',
      relayOrigin: 'https://relay.trisaura.io',
      webOrigin: 'https://trisaura.io',
      subjectDid: 'did:plc:abc23456789',
      approvingDeviceId: 'app_device_abc',
      scopes: const ['forum:read'],
      expiresAt: DateTime.utc(2026, 5, 11, 13),
      createdAt: DateTime.utc(2026, 5, 11, 12, 45),
    );

    final signed = await service.sign(grant);

    expect(signed.signatureHex, 'sig-hex');
    expect(utf8.decode(signer.lastMessage!), grant.canonicalJson());
  });

  test('parses valid app-mediated web session approval links', () {
    final link = WebSessionApprovalLink.parse(
      Uri.parse(
        'trisaura://web-session/approve?challenge_id=wsc_abc&relay_origin=https%3A%2F%2Frelay.trisaura.io',
      ),
    );

    expect(link.challengeId, 'wsc_abc');
    expect(link.relayOrigin, 'https://relay.trisaura.io');
  });

  test('rejects malformed approval links', () {
    expect(
      () => WebSessionApprovalLink.parse(
        Uri.parse('trisaura://web-session/approve?relay_origin=file:///tmp/x'),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

class _RecordingDidSigner implements DidSigner {
  List<int>? lastMessage;

  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    lastMessage = message;
    return const Ed25519Signature('sig-hex');
  }
}
