import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/services/public_profile_credential_preferences.dart';
import 'package:ansible_node/services/public_profile_credential_presentation_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'presents every selected VC with one shared authorized signer',
    () async {
      const holderDid = 'did:key:z6Mkholder';
      final now = DateTime.utc(2026, 8, 27, 12);
      final wallet = InMemoryWalletRepository();
      final preferences = MemoryPublicProfileCredentialPreferenceStore();
      final signer = _RecordingDidSigner();
      final client = _RecordingAtProtoClient();

      await _saveCredential(
        wallet,
        id: 'urn:uuid:humanity',
        holderDid: holderDid,
        type: 'TrisAuraHumanityCredential',
        claims: const {'humanVerified': true},
      );
      await _saveCredential(
        wallet,
        id: 'urn:uuid:adult',
        holderDid: holderDid,
        type: 'AgeOver18Credential',
        claims: const {'ageOver18': true},
      );
      for (final id in ['urn:uuid:humanity', 'urn:uuid:adult']) {
        await preferences.setSelected(
          holderDid: holderDid,
          credentialId: id,
          selected: true,
        );
      }

      final types =
          await PublicProfileCredentialPresentationService(
            walletRepository: wallet,
            preferenceStore: preferences,
            didSigner: signer,
            canonicalIdentityStore: InMemoryCanonicalIdentityStore(
              const CanonicalIdentity(
                did: holderDid,
                handle: 'holder.elix.cool',
                publicKeyHex: 'holder-public-key',
              ),
            ),
            clientFactory: (_) => client,
          ).presentSelected(
            holderDid: holderDid,
            node: RemoteNode(
              id: 'relay-prod',
              name: 'Relay',
              url: 'https://relay.example',
              isActive: true,
              createdAt: now,
              updatedAt: now,
            ),
            now: now,
          );

      expect(types, ['AgeOver18Credential', 'TrisAuraHumanityCredential']);
      expect(signer.signCalls, 2);
      expect(client.presentations, hasLength(2));
      expect(
        client.presentations.every((vp) => vp['holder'] == holderDid),
        isTrue,
      );
    },
  );

  test(
    'presents a VC bound to a verified legacy DID under the canonical holder',
    () async {
      const holderDid = 'did:elix:zcanonicalholder';
      const legacyDid = 'did:elix:legacyholder';
      final now = DateTime.utc(2026, 8, 27, 12);
      final wallet = InMemoryWalletRepository();
      final preferences = MemoryPublicProfileCredentialPreferenceStore();
      final client = _RecordingAtProtoClient();

      await _saveCredential(
        wallet,
        id: 'urn:uuid:legacy-humanity',
        holderDid: legacyDid,
        type: 'TrisAuraHumanityCredential',
        claims: const {'humanVerified': true},
      );
      await preferences.setSelected(
        holderDid: holderDid,
        credentialId: 'urn:uuid:legacy-humanity',
        selected: true,
      );

      final types =
          await PublicProfileCredentialPresentationService(
            walletRepository: wallet,
            preferenceStore: preferences,
            didSigner: _RecordingDidSigner(),
            canonicalIdentityStore: InMemoryCanonicalIdentityStore(
              const CanonicalIdentity(
                did: holderDid,
                handle: 'holder.elix.cool',
                publicKeyHex: 'canonical-public-key',
                legacyDids: [legacyDid],
              ),
            ),
            clientFactory: (_) => client,
          ).presentSelected(
            holderDid: holderDid,
            node: RemoteNode(
              id: 'relay-prod',
              name: 'Relay',
              url: 'https://relay.example',
              isActive: true,
              createdAt: now,
              updatedAt: now,
            ),
            now: now,
          );

      expect(types, ['TrisAuraHumanityCredential']);
      final vp = client.presentations.single;
      expect(vp['holder'], holderDid);
      final vc = (vp['verifiableCredential'] as List).single as Map;
      expect((vc['credentialSubject'] as Map)['id'], legacyDid);
    },
  );

  test(
    'rejects a VC bound to a DID outside the saved identity aliases',
    () async {
      const holderDid = 'did:elix:zcanonicalholder';
      const foreignDid = 'did:elix:foreignholder';
      final now = DateTime.utc(2026, 8, 27, 12);
      final wallet = InMemoryWalletRepository();
      final preferences = MemoryPublicProfileCredentialPreferenceStore();

      await _saveCredential(
        wallet,
        id: 'urn:uuid:foreign-humanity',
        holderDid: foreignDid,
        type: 'TrisAuraHumanityCredential',
        claims: const {'humanVerified': true},
      );
      await preferences.setSelected(
        holderDid: holderDid,
        credentialId: 'urn:uuid:foreign-humanity',
        selected: true,
      );

      final service = PublicProfileCredentialPresentationService(
        walletRepository: wallet,
        preferenceStore: preferences,
        didSigner: _RecordingDidSigner(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(
          const CanonicalIdentity(
            did: holderDid,
            handle: 'holder.elix.cool',
            publicKeyHex: 'canonical-public-key',
            legacyDids: ['did:elix:verifiedlegacy'],
          ),
        ),
        clientFactory: (_) => _RecordingAtProtoClient(),
      );

      await expectLater(
        service.presentSelected(
          holderDid: holderDid,
          node: RemoteNode(
            id: 'relay-prod',
            name: 'Relay',
            url: 'https://relay.example',
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'public_profile_credential_unavailable',
          ),
        ),
      );
    },
  );
}

Future<void> _saveCredential(
  InMemoryWalletRepository wallet, {
  required String id,
  required String holderDid,
  required String type,
  required Map<String, Object?> claims,
}) {
  final validFrom = DateTime.utc(2026, 8, 1);
  final validUntil = DateTime.utc(2027, 8, 1);
  return wallet.saveCredential(
    metadata: WalletCredential(
      credentialId: id,
      issuerDid: 'did:web:issuer.elix.cool',
      holderDid: holderDid,
      credentialType: type,
      status: WalletCredentialStatus.active,
      validFrom: validFrom,
      validUntil: validUntil,
      displayName: type,
      createdAt: validFrom,
      updatedAt: validFrom,
    ),
    encryptedPayload: jsonEncode({
      '@context': [
        'https://www.w3.org/ns/credentials/v2',
        'https://elix.cool/contexts/profile/v1',
      ],
      'id': id,
      'type': ['VerifiableCredential', type],
      'issuer': 'did:web:issuer.elix.cool',
      'validFrom': validFrom.toIso8601String(),
      'validUntil': validUntil.toIso8601String(),
      'credentialSubject': {'id': holderDid, ...claims},
      'proof': {
        'type': 'DataIntegrityProof',
        'cryptosuite': 'eddsa-jcs-2022',
        'created': validFrom.toIso8601String(),
        'verificationMethod': 'did:web:issuer.elix.cool#key-1',
        'proofPurpose': 'assertionMethod',
        'proofValue': 'zissuerproof',
      },
    }),
    encryptionVersion: 'test-json',
  );
}

class _RecordingDidSigner implements DidSigner {
  int signCalls = 0;

  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    signCalls += 1;
    return const Ed25519Signature('holder-proof');
  }
}

class _RecordingAtProtoClient extends AtProtoClient {
  _RecordingAtProtoClient() : super(baseUrl: 'https://relay.example');

  final List<Map<String, dynamic>> presentations = [];

  @override
  Future<Map<String, dynamic>> presentPublicProfileCredential({
    required String holderDid,
    required Map<String, dynamic> vp,
  }) async {
    presentations.add(vp);
    return {'credential_type': 'verified'};
  }
}
