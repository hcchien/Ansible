import 'dart:convert';
import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_node/services/authority_witness_client.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'anchor success requires direct acknowledgement from configured observer',
    () async {
      final urls = <String>[];
      var allow = false;
      final client = MockClient((r) async {
        urls.add(r.url.toString());
        if (r.url.host == 'relay.example') {
          return http.Response(
            jsonEncode({'state': 'active', 'anchor_cid': 'cid'}),
            201,
          );
        }
        expect(r.url.host, 'observer.example');
        expect(r.followRedirects, isFalse);
        return http.Response(
          jsonEncode(
            allow ? {'sequence': 1} : {'error': 'authority_rollback_or_fork'},
          ),
          allow ? 200 : 409,
        );
      });
      final anchor = IdentityAnchor.fromMap({
        'type': IdentityAnchor.typeName,
        'schema_version': 3,
        'did': 'did:elix:test',
        'identity_key': 'aa' * 32,
        'identity_key_algorithm': 'ed25519',
        'handle': 'test.elix.cool',
        'custody_class': 'software',
        'devices': [],
        'also_known_as': [],
        'prev_anchor_cid': null,
        'reason': 'initial',
        'created_at': '2026-01-01T00:00:00Z',
        'sig': 'bb' * 64,
      });
      final relay = RelayAnchorClient(
        baseUrl: 'https://relay.example',
        client: client,
        authorityWitness: AuthorityWitnessClient(
          baseUrl: 'https://observer.example',
          client: client,
        ),
      );
      await expectLater(relay.submitAnchor(anchor), throwsStateError);
      expect(urls, [
        'https://relay.example/api/v1/identity/anchor',
        'https://observer.example/api/v1/authority/checkpoint',
      ]);
      allow = true;
      expect((await relay.submitAnchor(anchor)).state, AnchorState.active);
    },
  );

  test(
    'revalidation only signs this holder’s locally sent public bytes',
    () async {
      final requests = <Map<String, dynamic>>[];
      final signer = _Signer();
      final witness = AuthorityWitnessClient(
        baseUrl: 'https://observer.example',
        client: MockClient((r) async {
          expect(
            r.url.toString(),
            'https://observer.example/api/v1/authority/revalidate',
          );
          expect(r.followRedirects, isFalse);
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{"revalidated":true}', 200);
        }),
      );
      OpsQueueEntry entry(
        String id,
        String visibility, {
        String author = 'did:elix:owner',
        String status = 'synced',
      }) => OpsQueueEntry(
        opId: id,
        authorDid: author,
        entityType: 'note',
        entityId: id,
        opType: 'insert',
        payload: base64.encode(
          utf8.encode(
            jsonEncode({'body': 'local $id', 'visibility': visibility}),
          ),
        ),
        signature: 'aa' * 64,
        status: status,
        createdAt: DateTime.utc(2026),
      );
      final original = entry('public', 'public');
      final count = await witness.revalidatePublicHistory(
        [
          original,
          entry('private', 'private'),
          entry('other', 'public', author: 'did:elix:other'),
          entry('draft', 'public', status: 'pending'),
        ],
        did: 'did:elix:owner',
        signer: signer,
      );
      expect(count, 1);
      expect(signer.messages.length, 1);
      expect(requests.length, 1);
      final wire = requests.single;
      final operation = wire['operation'] as Map<String, dynamic>;
      final canonical = jsonEncode({
        'author_did': original.authorDid,
        'entity_id': original.entityId,
        'entity_type': original.entityType,
        'op_id': original.opId,
        'op_type': original.opType,
        'payload': original.payload,
      });
      expect(
        wire['authorization']['operation_digest'],
        sha256
            .convert(utf8.encode('$canonical\u0000${original.signature}'))
            .toString(),
      );
      expect(operation['payload'], original.payload);
      expect(
        wire['authorization']['observer_origin'],
        'https://observer.example',
      );
      expect(jsonDecode(signer.messages.single), wire['authorization']);
    },
  );

  test('observer redirects and insecure remote origins fail closed', () async {
    final body = {'subject_did': 'did:elix:test'};
    final redirect = AuthorityWitnessClient(
      baseUrl: 'https://observer.example',
      client: MockClient((r) async {
        expect(r.followRedirects, isFalse);
        return http.Response(
          '',
          307,
          headers: {'location': 'https://relay.example'},
        );
      }),
    );
    await expectLater(redirect.revoke(body, 'signature'), throwsStateError);
    final insecure = AuthorityWitnessClient(
      baseUrl: 'http://observer.example',
      client: MockClient((_) async => throw StateError('must not send')),
    );
    await expectLater(insecure.revoke(body, 'signature'), throwsStateError);
  });
}

class _Signer implements DidSigner {
  final messages = <String>[];
  @override
  Future<Ed25519Signature> sign(List<int> bytes) async {
    messages.add(utf8.decode(bytes));
    return Ed25519Signature('ab' * 64);
  }
}
