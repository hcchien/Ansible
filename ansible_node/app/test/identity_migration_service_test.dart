import 'dart:convert';

import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/screens/identity_migration_screen.dart';
import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/identity_migration_service.dart';
import 'package:ansible_node/services/recovery_readiness_store.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('completes a resumable same-account v1 migration', () async {
    final harness = _Harness();
    final migrated = await harness.service.migrate();

    expect(migrated.did, harness.v1Did);
    expect(migrated.handle, 'alice.elix.cool');
    expect(migrated.legacyDids, [harness.legacyDid]);
    expect(migrated.genesisCommitment, isNotNull);
    expect(await harness.checkpoints.load(), isNull);
    expect(harness.v1AnchorPosts, 1);
    expect(harness.migrationPosts, 1);

    final stored = await harness.identities.load();
    expect(stored?.did, harness.v1Did);
    expect(
      await const FlutterSecureStorage().read(key: 'ansible_passkeys_did'),
      harness.v1Did,
    );
  });

  test('does not switch locally until a timed-out commit is re-read', () async {
    final harness = _Harness(failFirstConfirmation: true);

    await expectLater(
      harness.service.migrate(),
      throwsA(isA<IdentityMigrationException>()),
    );
    expect((await harness.identities.load())?.did, harness.legacyDid);
    expect(
      (await harness.checkpoints.load())?.phase,
      IdentityMigrationPhase.anchorPublished,
    );

    final migrated = await harness.service.migrate();
    expect(migrated.did, harness.v1Did);
    expect(harness.v1AnchorPosts, 1);
    expect(harness.migrationPosts, 1);
    expect(await harness.checkpoints.load(), isNull);
  });

  testWidgets('requires informed consent before starting the product flow', (
    tester,
  ) async {
    final harness = _Harness();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    CanonicalIdentity? completed;

    await tester.pumpWidget(
      MaterialApp(
        home: IdentityMigrationScreen(
          db: db,
          did: harness.legacyDid,
          service: harness.service,
          onCompleted: (identity) => completed = identity,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final start = find.byKey(const Key('identity_migration_start'));
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await tester.tap(find.byKey(const Key('identity_migration_consent')));
    await tester.pump();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);

    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('identity_migration_new_did')), findsOneWidget);
    expect(completed, isNull);

    await tester.tap(find.byKey(const Key('identity_migration_done')));
    await tester.pumpAndSettle();
    expect(completed?.did, harness.v1Did);
  });
}

class _Harness {
  _Harness({this.failFirstConfirmation = false}) {
    identities = InMemoryCanonicalIdentityStore(
      CanonicalIdentity(
        did: legacyDid,
        handle: 'alice.elix.cool',
        publicKeyHex: publicKeyHex,
        signingAlgorithm: 'ed25519',
        custody: 'reduced_trust',
      ),
    );
    checkpoints = InMemoryIdentityMigrationCheckpointStore();
    v1Did = deriveDidElixV1(
      genesisKey: publicKeyHex,
      genesisNonceHex: '01' * 32,
    );
    final legacyAnchor = IdentityAnchor(
      did: legacyDid,
      handle: 'alice.elix.cool',
      identityKey: publicKeyHex,
      identityKeyAlgorithm: 'ed25519',
      custodyClass: CustodyClass.software,
      reason: AnchorReason.initial,
      createdAt: DateTime.utc(2026, 8, 19),
      sig: 'legacy-signature',
    );

    final httpClient = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' &&
          path.contains('/api/v1/identity/migration/')) {
        if (_migration == null) return http.Response('{}', 404);
        if (failFirstConfirmation && !_confirmationFailed) {
          _confirmationFailed = true;
          return http.Response(
            jsonEncode({'error': 'migration_unavailable', 'retryable': true}),
            503,
          );
        }
        return http.Response(jsonEncode(_migration), 200);
      }
      if (request.method == 'GET' &&
          path.contains('/api/v1/identity/anchor/')) {
        final did = Uri.decodeComponent(path.split('/').last);
        if (did == legacyDid) {
          return http.Response(
            jsonEncode({
              ...legacyAnchor.toCanonicalMap(),
              'canonical_body': legacyAnchor.canonicalBodyJson(),
            }),
            200,
          );
        }
        if (did == v1Did && _v1Anchor != null) {
          return http.Response(
            jsonEncode({
              ..._v1Anchor!.toCanonicalMap(),
              'canonical_body': _v1Anchor!.canonicalBodyJson(),
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }
      if (request.method == 'POST' && path == '/api/v1/identity/anchor') {
        v1AnchorPosts += 1;
        _v1Anchor = IdentityAnchor.fromMap(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
        return http.Response(
          jsonEncode({
            'state': 'active',
            'anchor_cid': _v1Anchor!.computeCid(),
          }),
          201,
        );
      }
      if (request.method == 'POST' && path == '/api/v1/identity/migration') {
        migrationPosts += 1;
        final submitted = (jsonDecode(request.body) as Map)
            .cast<String, Object?>();
        final unsigned = <String, Object?>{
          'type': submitted['type'],
          'version': submitted['version'],
          'legacy_did': submitted['legacy_did'],
          'v1_did': submitted['v1_did'],
          'created_at': submitted['created_at'],
        };
        _migration = {
          ...submitted,
          'handle': 'alice.elix.cool',
          'state': 'completed',
          'canonical_body': jsonEncode(unsigned),
        };
        return http.Response(jsonEncode(_migration), 201);
      }
      return http.Response('{}', 404);
    });

    final anchors = InMemoryIdentityAnchorRepository();
    final anchorClient = RelayAnchorClient(
      baseUrl: 'https://relay.test',
      client: httpClient,
    );
    final anchorService = IdentityAnchorService(
      relayClient: anchorClient,
      anchorRepository: anchors,
      deviceKeyStore: InMemoryDeviceKeyStore(),
      readinessStore: InMemoryRecoveryReadinessStore(),
      now: () => DateTime.utc(2026, 8, 19, 1),
    );
    service = IdentityMigrationService(
      anchorService: anchorService,
      anchorRepository: anchors,
      anchorClient: anchorClient,
      migrationClient: RelayIdentityMigrationClient(
        baseUrl: 'https://relay.test',
        client: httpClient,
      ),
      identityStore: identities,
      checkpointStore: checkpoints,
      identityKey: _FakeIdentityKey(publicKeyHex),
      now: () => DateTime.utc(2026, 8, 19, 2),
      nonceHex: () => '01' * 32,
    );
  }

  final bool failFirstConfirmation;
  final String legacyDid = 'did:elix:abcdefghijklmnop';
  final String publicKeyHex = '11' * 32;
  late final String v1Did;
  late final InMemoryCanonicalIdentityStore identities;
  late final InMemoryIdentityMigrationCheckpointStore checkpoints;
  late final IdentityMigrationService service;
  IdentityAnchor? _v1Anchor;
  Map<String, Object?>? _migration;
  bool _confirmationFailed = false;
  int v1AnchorPosts = 0;
  int migrationPosts = 0;
}

class _FakeIdentityKey implements IdentityKey {
  const _FakeIdentityKey(this.key);

  final String key;

  @override
  Future<String> algorithm() async => 'ed25519';

  @override
  Future<CustodyClass> custodyClass() async => CustodyClass.software;

  @override
  Future<String> publicKeyHex() async => key;

  @override
  Future<String> sign(List<int> message) async {
    return 'ab' * 64;
  }
}
