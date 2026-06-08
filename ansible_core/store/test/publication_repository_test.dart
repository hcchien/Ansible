import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('publication repositories', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('drift enforces federation signing policy', () async {
      await _exercisesPublicationRepository(DriftPublicationRepository(db));
    });

    test('in-memory enforces federation signing policy', () async {
      await _exercisesPublicationRepository(InMemoryPublicationRepository());
    });
  });
}

Future<void> _exercisesPublicationRepository(
  PublicationRepository repository,
) async {
  final now = DateTime.utc(2026, 5, 9);

  await expectLater(
    repository.enqueueIntent(
      _intent(
        id: 'intent-private',
        visibility: ContentVisibility.private,
        distributionPreference: DistributionPreference.localOnly,
        createdAt: now,
      ),
      targets: [
        _target(
          id: 'target-private',
          intentId: 'intent-private',
          protocol: PublicationProtocol.nostr,
        ),
      ],
    ),
    throwsA(isA<ArgumentError>()),
  );

  await repository.enqueueIntent(
    _intent(
      id: 'intent-unsigned',
      visibility: ContentVisibility.public,
      distributionPreference: DistributionPreference.nostr,
      createdAt: now,
    ),
    targets: [
      _target(
        id: 'target-unsigned',
        intentId: 'intent-unsigned',
        protocol: PublicationProtocol.nostr,
      ),
    ],
  );

  await repository.enqueueIntent(
    _intent(
      id: 'intent-dev-signed',
      visibility: ContentVisibility.unlisted,
      distributionPreference: DistributionPreference.activityPub,
      signature: 'dev-signature-placeholder',
      signatureScheme: 'ed25519',
      signedAt: now,
      createdAt: now.add(const Duration(seconds: 1)),
    ),
    targets: [
      _target(
        id: 'target-dev-signed',
        intentId: 'intent-dev-signed',
        protocol: PublicationProtocol.activityPub,
      ),
    ],
  );

  expect(await repository.listPendingTargets(), isEmpty);

  await repository.enqueueIntent(
    _intent(
      id: 'intent-signed',
      visibility: ContentVisibility.public,
      distributionPreference: DistributionPreference.nostrAndActivityPub,
      signature: 'a' * 128,
      signatureScheme: 'ed25519',
      signedAt: now,
      createdAt: now.add(const Duration(seconds: 2)),
    ),
    targets: [
      _target(
        id: 'target-nostr',
        intentId: 'intent-signed',
        protocol: PublicationProtocol.nostr,
      ),
      _target(
        id: 'target-activitypub',
        intentId: 'intent-signed',
        protocol: PublicationProtocol.activityPub,
      ),
    ],
  );

  final nostrTargets = await repository.listPendingTargets(
    protocol: PublicationProtocol.nostr,
  );
  expect(nostrTargets.map((target) => target.targetId), ['target-nostr']);

  await repository.markTargetFailed('target-nostr', 'signer unavailable');
  expect(
    await repository.listPendingTargets(protocol: PublicationProtocol.nostr),
    isEmpty,
  );
  expect(
    (await repository.getTargetById('target-nostr'))!.error,
    'signer unavailable',
  );

  final failedTargets = await repository.listTargets(
    protocol: PublicationProtocol.nostr,
    status: PublicationStatus.failed,
  );
  expect(failedTargets.map((target) => target.targetId), ['target-nostr']);

  await repository.resetTargetForRetry('target-nostr');
  final retryTarget = (await repository.getTargetById('target-nostr'))!;
  expect(retryTarget.status, PublicationStatus.pending);
  expect(retryTarget.error, isNull);

  await repository.markTargetPublished(
    'target-activitypub',
    remoteId: 'https://relay.elix.cool/users/alice/outbox/1',
  );
  await repository.markIntentComplete('intent-signed');

  final signedIntent = await repository.getIntentById('intent-signed');
  expect(signedIntent!.status, PublicationStatus.complete);

  final targets = await repository.listTargetsForIntent('intent-signed');
  final statusById = {
    for (final target in targets) target.targetId: target.status,
  };
  expect(statusById['target-nostr'], PublicationStatus.pending);
  expect(statusById['target-activitypub'], PublicationStatus.published);
  expect(
    targets.singleWhere((target) => target.targetId == 'target-nostr').error,
    isNull,
  );

  await repository.saveIdentityBinding(
    IdentityBinding(
      bindingId: 'binding-nostr',
      localAccountDid: 'did:plc:alice',
      bindingType: IdentityBindingType.nostr,
      identifier: 'npub1alice',
      publicKey: 'b' * 64,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final bindings = await repository.bindingsForAccount('did:plc:alice');
  expect(bindings.single.bindingType, IdentityBindingType.nostr);
  expect(bindings.single.publicKey, 'b' * 64);
}

PublicationIntent _intent({
  required String id,
  required ContentVisibility visibility,
  required DistributionPreference distributionPreference,
  required DateTime createdAt,
  String? signature,
  String? signatureScheme,
  DateTime? signedAt,
}) {
  return PublicationIntent(
    intentId: id,
    authorDid: 'did:plc:alice',
    contentItemId: 'content-$id',
    action: PublicationAction.publish,
    visibility: visibility,
    distributionPreference: distributionPreference,
    status: PublicationStatus.pending,
    signature: signature,
    signatureScheme: signatureScheme,
    signedAt: signedAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

PublicationTarget _target({
  required String id,
  required String intentId,
  required PublicationProtocol protocol,
}) {
  return PublicationTarget(
    targetId: id,
    intentId: intentId,
    protocol: protocol,
    endpoint: protocol == PublicationProtocol.nostr
        ? 'wss://relay.example'
        : 'https://relay.elix.cool',
    status: PublicationStatus.pending,
  );
}
