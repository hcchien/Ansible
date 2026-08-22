import 'package:ansible_node/screens/onboarding_backup_step_screen.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/recovery_readiness_store.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A 32-byte Ed25519 seed hex. Not real.
const _keyHex =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';

/// Records every anchor submitted so the test can assert publishInitialAnchor
/// ran and produced an `initial` anchor.
class _RecordingRelayClient extends RelayAnchorClient {
  _RecordingRelayClient() : super(baseUrl: 'http://relay.local');

  final List<IdentityAnchor> submitted = [];

  @override
  Future<AnchorSubmitResult> submitAnchor(
    IdentityAnchor anchor, {
    String? recoveryProof,
  }) async {
    submitted.add(anchor);
    return const AnchorSubmitResult(
      state: AnchorState.active,
      anchorCid: 'sha256:initial',
      statusCode: 201,
    );
  }
}

IdentityAnchorService _service(_RecordingRelayClient relay) {
  return IdentityAnchorService(
    relayClient: relay,
    anchorRepository: InMemoryIdentityAnchorRepository(),
    deviceKeyStore: InMemoryDeviceKeyStore(),
    readinessStore: InMemoryRecoveryReadinessStore(),
    now: () => DateTime.utc(2026, 6, 16),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('new v1 identity publishes the persisted schema v4 commitment', (
    tester,
  ) async {
    final relay = _RecordingRelayClient();
    final identityKey = InMemoryIdentityKey(_keyHex);
    final publicKey = await identityKey.publicKeyHex();
    final commitment = buildDidElixV1GenesisCommitment(
      genesisKey: publicKey,
      genesisNonceHex: '01' * 32,
    );
    final did = deriveDidElixV1(
      genesisKey: publicKey,
      genesisNonceHex: '01' * 32,
    );
    final canonicalStore = InMemoryCanonicalIdentityStore(
      CanonicalIdentity(
        did: did,
        handle: 'v1.elix.cool',
        publicKeyHex: publicKey,
        genesisCommitment: commitment,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: did,
          handle: 'v1.elix.cool',
          anchorService: _service(relay),
          identityKeyForAnchor: identityKey,
          canonicalIdentityStore: canonicalStore,
          readinessStore: InMemoryRecoveryReadinessStore(),
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(relay.submitted.single.schemaVersion, 4);
    expect(relay.submitted.single.genesisCommitment, commitment);
  });

  testWidgets('publishInitialAnchor is invoked after the v2 anchor', (
    tester,
  ) async {
    final relay = _RecordingRelayClient();
    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: 'did:plc:alice',
          handle: 'alice.elix.cool',
          anchorService: _service(relay),
          identityKeyForAnchor: InMemoryIdentityKey(_keyHex),
          readinessStore: InMemoryRecoveryReadinessStore(),
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(relay.submitted, hasLength(1));
    expect(relay.submitted.single.reason, AnchorReason.initial);
    expect(relay.submitted.single.did, 'did:plc:alice');
    // zh-Hant copy (test locale falls back to zh-Hant).
    expect(find.text('帳號已建立'), findsOneWidget);
  });

  testWidgets('the backup step appears after create', (tester) async {
    final relay = _RecordingRelayClient();
    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: 'did:plc:alice',
          handle: 'alice.elix.cool',
          anchorService: _service(relay),
          identityKeyForAnchor: InMemoryIdentityKey(_keyHex),
          readinessStore: InMemoryRecoveryReadinessStore(),
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding_backup_button')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    // The skippable warning copy is present.
    expect(find.textContaining('沒有備份'), findsOneWidget);
  });

  testWidgets('skipping sets the nag flag and leaves readiness false', (
    tester,
  ) async {
    final relay = _RecordingRelayClient();
    final store = InMemoryRecoveryReadinessStore();
    String? completedDid;
    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: 'did:plc:alice',
          handle: 'alice.elix.cool',
          anchorService: _service(relay),
          identityKeyForAnchor: InMemoryIdentityKey(_keyHex),
          readinessStore: store,
          onComplete: (did) => completedDid = did,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding_skip_button')));
    await tester.pumpAndSettle();

    expect(completedDid, 'did:plc:alice');
    expect(await store.hasBackup(), isFalse);
    expect(await store.shouldNagForBackup(), isTrue);
  });

  testWidgets('tapping create backup opens the backup screen', (tester) async {
    final relay = _RecordingRelayClient();
    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: 'did:plc:alice',
          handle: 'alice.elix.cool',
          anchorService: _service(relay),
          identityKeyForAnchor: InMemoryIdentityKey(_keyHex),
          identityPrivateKeyHex: () async => _keyHex,
          readinessStore: InMemoryRecoveryReadinessStore(),
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding_backup_button')));
    await tester.pumpAndSettle();

    // The reused IdentityBackupScreen is now on screen.
    expect(find.byKey(const Key('backup_passphrase_field')), findsOneWidget);
    expect(find.byKey(const Key('backup_create_button')), findsOneWidget);
  });

  testWidgets('completing the backup (readiness true) finishes onboarding', (
    tester,
  ) async {
    // When the backup screen returns and a backup exists, the step completes
    // onboarding into the app. We seed readiness=true to simulate a completed
    // backup without driving the real PBKDF2 path (covered by the store tests).
    final relay = _RecordingRelayClient();
    final store = InMemoryRecoveryReadinessStore(
      backupAt: DateTime.utc(2026, 6, 16),
    );
    String? completedDid;
    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: 'did:plc:alice',
          handle: 'alice.elix.cool',
          anchorService: _service(relay),
          identityKeyForAnchor: InMemoryIdentityKey(_keyHex),
          identityPrivateKeyHex: () async => _keyHex,
          readinessStore: store,
          onComplete: (did) => completedDid = did,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open then immediately back out of the backup screen; because readiness is
    // already true, the step treats it as a completed backup and finishes.
    await tester.tap(find.byKey(const Key('onboarding_backup_button')));
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byKey(const Key('backup_create_button'))),
    ).pop();
    await tester.pumpAndSettle();

    expect(completedDid, 'did:plc:alice');
    expect(await store.hasBackup(), isTrue);
  });

  testWidgets('publishInitialAnchor failure is tolerated (account still works)', (
    tester,
  ) async {
    // A relay that throws on submit — the step must still let the user proceed.
    final service = IdentityAnchorService(
      relayClient: _ThrowingRelayClient(),
      anchorRepository: InMemoryIdentityAnchorRepository(),
      deviceKeyStore: InMemoryDeviceKeyStore(),
      readinessStore: InMemoryRecoveryReadinessStore(),
      now: () => DateTime.utc(2026, 6, 16),
    );
    String? completedDid;
    await tester.pumpWidget(
      _wrap(
        OnboardingBackupStepScreen(
          did: 'did:plc:alice',
          handle: 'alice.elix.cool',
          anchorService: service,
          identityKeyForAnchor: InMemoryIdentityKey(_keyHex),
          readinessStore: InMemoryRecoveryReadinessStore(),
          onComplete: (did) => completedDid = did,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Recovery-not-set-up warning is surfaced, but the user can still proceed.
    expect(find.byKey(const Key('onboarding_anchor_warning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_skip_button')));
    await tester.pumpAndSettle();
    expect(completedDid, 'did:plc:alice');
  });
}

class _ThrowingRelayClient extends RelayAnchorClient {
  _ThrowingRelayClient() : super(baseUrl: 'http://relay.local');

  @override
  Future<AnchorSubmitResult> submitAnchor(
    IdentityAnchor anchor, {
    String? recoveryProof,
  }) async {
    throw const RelayAnchorException(
      statusCode: 500,
      responseBody: 'boom',
      error: 'server_error',
    );
  }
}
