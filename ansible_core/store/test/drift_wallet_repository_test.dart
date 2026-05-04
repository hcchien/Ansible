import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/drift/drift_wallet_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:ansible_store/src/db/app_database.dart';

void main() {
  group('DriftWalletRepository', () {
    late AppDatabase db;
    late DriftWalletRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftWalletRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'stores encrypted credential payload separately from metadata',
      () async {
        final credential = entity.WalletCredential(
          credentialId: 'urn:uuid:test-humanity',
          issuerDid: 'did:web:issuer.trisaura.io',
          holderDid: 'did:key:z6Mkholder',
          credentialType: 'TrisAuraHumanityCredential',
          status: entity.WalletCredentialStatus.active,
          validFrom: DateTime.utc(2026, 5, 4),
          validUntil: DateTime.utc(2026, 8, 2),
          displayName: 'Verified Human',
          createdAt: DateTime.utc(2026, 5, 4, 10),
          updatedAt: DateTime.utc(2026, 5, 4, 10),
        );

        await repo.saveCredential(
          metadata: credential,
          encryptedPayload: 'ciphertext-not-json',
          encryptionVersion: 'local-dev-v1',
        );

        final credentials = await repo.listCredentials();
        expect(credentials.single.credentialId, 'urn:uuid:test-humanity');
        expect(credentials.single.displayName, 'Verified Human');
        expect(credentials.single.status, entity.WalletCredentialStatus.active);

        final payload = await repo.getEncryptedPayload(
          'urn:uuid:test-humanity',
        );
        expect(payload, 'ciphertext-not-json');
        expect(payload, isNot(contains('humanVerified')));
      },
    );

    test('updates credential status without rewriting payload', () async {
      final credential = entity.WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.trisaura.io',
        holderDid: 'did:key:z6Mkholder',
        credentialType: 'TrisAuraHumanityCredential',
        status: entity.WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 4),
        validUntil: DateTime.utc(2026, 8, 2),
        displayName: 'Verified Human',
        createdAt: DateTime.utc(2026, 5, 4, 10),
        updatedAt: DateTime.utc(2026, 5, 4, 10),
      );

      await repo.saveCredential(
        metadata: credential,
        encryptedPayload: 'original-ciphertext',
        encryptionVersion: 'local-dev-v1',
      );

      await repo.updateCredentialStatus(
        'urn:uuid:test-humanity',
        entity.WalletCredentialStatus.revoked,
        updatedAt: DateTime.utc(2026, 5, 5),
      );

      final updated = await repo.getCredential('urn:uuid:test-humanity');
      expect(updated!.status, entity.WalletCredentialStatus.revoked);
      expect(
        updated.updatedAt.isAtSameMomentAs(DateTime.utc(2026, 5, 5)),
        isTrue,
      );
      expect(
        await repo.getEncryptedPayload('urn:uuid:test-humanity'),
        'original-ciphertext',
      );
    });

    test('records presentation metadata without claim payloads', () async {
      final presentation = entity.WalletPresentation(
        presentationId: 'vp-1',
        credentialId: 'urn:uuid:test-humanity',
        verifierAudience: 'https://relay.trisaura.io',
        nonceHash: 'sha256-nonce',
        result: entity.WalletPresentationResult.approved,
        createdAt: DateTime.utc(2026, 5, 4, 10),
      );

      await repo.recordPresentation(presentation);

      final history = await repo.listPresentations('urn:uuid:test-humanity');
      expect(history.single.result, entity.WalletPresentationResult.approved);
      expect(history.single.nonceHash, 'sha256-nonce');
      expect(history.single.verifierAudience, 'https://relay.trisaura.io');
    });

    test(
      'delete removes local credential metadata and encrypted payload',
      () async {
        final credential = entity.WalletCredential(
          credentialId: 'urn:uuid:test-humanity',
          issuerDid: 'did:web:issuer.trisaura.io',
          holderDid: 'did:key:z6Mkholder',
          credentialType: 'TrisAuraHumanityCredential',
          status: entity.WalletCredentialStatus.active,
          validFrom: DateTime.utc(2026, 5, 4),
          validUntil: DateTime.utc(2026, 8, 2),
          displayName: 'Verified Human',
          createdAt: DateTime.utc(2026, 5, 4, 10),
          updatedAt: DateTime.utc(2026, 5, 4, 10),
        );

        await repo.saveCredential(
          metadata: credential,
          encryptedPayload: 'ciphertext-not-json',
          encryptionVersion: 'local-dev-v1',
        );

        await repo.deleteCredential('urn:uuid:test-humanity');

        expect(await repo.getCredential('urn:uuid:test-humanity'), isNull);
        expect(
          await repo.getEncryptedPayload('urn:uuid:test-humanity'),
          isNull,
        );
        expect(await repo.listCredentials(), isEmpty);
      },
    );

    test('delete removes presentation history for the credential', () async {
      final credential = entity.WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.trisaura.io',
        holderDid: 'did:key:z6Mkholder',
        credentialType: 'TrisAuraHumanityCredential',
        status: entity.WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 4),
        validUntil: DateTime.utc(2026, 8, 2),
        displayName: 'Verified Human',
        createdAt: DateTime.utc(2026, 5, 4, 10),
        updatedAt: DateTime.utc(2026, 5, 4, 10),
      );

      await repo.saveCredential(
        metadata: credential,
        encryptedPayload: 'ciphertext-not-json',
        encryptionVersion: 'local-dev-v1',
      );
      await repo.recordPresentation(
        entity.WalletPresentation(
          presentationId: 'vp-1',
          credentialId: 'urn:uuid:test-humanity',
          verifierAudience: 'https://relay.trisaura.io',
          nonceHash: 'sha256-nonce',
          result: entity.WalletPresentationResult.approved,
          createdAt: DateTime.utc(2026, 5, 4, 10),
        ),
      );

      await repo.deleteCredential('urn:uuid:test-humanity');

      expect(await repo.listPresentations('urn:uuid:test-humanity'), isEmpty);
    });
  });
}
