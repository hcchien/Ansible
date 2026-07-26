import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_node/services/fediverse_preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'signs and sends explicit Fediverse consent to the active Relay',
    () async {
      Map<String, dynamic>? requestBody;
      final store = _MemoryStore();
      final controller = FediversePreferencesController(
        did: 'did:key:alice',
        remoteNodes: _RemoteNodes(),
        store: store,
        signer: _Signer(),
        syncCapabilityProvider: (_) async => 'sync-token',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer sync-token');
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              ...requestBody!,
              'actor': 'alice',
              'allowed_domains': ['friends.example', 'social.example'],
            }),
            200,
          );
        }),
      );

      await controller.load();
      await controller.update(
        controller.preferences.copyWith(
          enabled: true,
          domainPolicy: FediverseDomainPolicy.allowlist,
          allowedDomains: ['Social.Example.', 'friends.example'],
          blockedDomains: ['bad.example'],
        ),
      );

      expect(requestBody!['did'], 'did:key:alice');
      expect(requestBody!['enabled'], isTrue);
      expect(requestBody!['domain_policy'], 'allowlist');
      expect(requestBody!['allowed_domains'], [
        'friends.example',
        'social.example',
      ]);
      expect(requestBody!['signature'], 'aa' * 64);
      expect(requestBody!['signature_scheme'], 'ed25519');
      expect(controller.preferences.enabled, isTrue);
      expect(store.saved?.enabled, isTrue);
    },
  );

  test('does not persist a preference rejected by the Relay', () async {
    final store = _MemoryStore();
    final controller = FediversePreferencesController(
      did: 'did:key:basic',
      remoteNodes: _RemoteNodes(),
      store: store,
      signer: _Signer(),
      syncCapabilityProvider: (_) async => 'sync-token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'activity_pub_requires_verified_human'}),
          403,
        ),
      ),
    );

    await controller.load();

    await expectLater(
      controller.setEnabled(true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'activity_pub_requires_verified_human',
        ),
      ),
    );
    expect(controller.preferences.enabled, isFalse);
    expect(store.saved, isNull);
  });
}

class _MemoryStore implements FediversePreferencesStore {
  FediversePreferences? saved;

  @override
  Future<FediversePreferences> load(String did) async =>
      const FediversePreferences();

  @override
  Future<void> save(String did, FediversePreferences preferences) async {
    saved = preferences;
  }
}

class _Signer implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async =>
      Ed25519Signature('aa' * 64);
}

class _RemoteNodes implements RemoteNodeRepository {
  final node = RemoteNode(
    id: 'relay',
    name: 'Relay',
    url: 'https://relay.example/',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<RemoteNode?> getActive() async => node;

  @override
  Future<RemoteNode?> getById(String id) async => id == node.id ? node : null;

  @override
  Future<List<RemoteNode>> list() async => [node];

  @override
  Future<void> create(RemoteNode node) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> update(RemoteNode node) async {}

  @override
  Future<void> updateSyncCursor(
    String id,
    int cursor,
    DateTime syncTime,
  ) async {}
}
