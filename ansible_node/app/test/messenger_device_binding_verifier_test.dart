import 'dart:convert';

import 'package:ansible_node/services/messenger_device_binding_verifier.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const subjectDid = 'did:elix:bob';
  const expectedBinding = <String, Object?>{
    'type': 'io.trisaura.messengerDeviceBinding',
    'version': 1,
    'subject_did': subjectDid,
    'device_id': 'msgdev_bob',
    'messenger_identity_key': 'bob_identity',
    'signed_pre_key_id': 42,
    'signed_pre_key': 'bob_signed_pre_key',
  };

  test(
    'verifies the exact canonical binding with an independently resolved key',
    () async {
      List<int>? verifiedMessage;
      final verifier = DidMessengerDeviceBindingVerifier(
        resolveVerificationKey: (did) async {
          expect(did, subjectDid);
          return const MessengerDidVerificationKey(
            publicKeyHex: 'identity_public_key',
            algorithm: 'ed25519',
          );
        },
        verifySignature:
            ({required key, required message, required signatureHex}) async {
              expect(key.publicKeyHex, 'identity_public_key');
              expect(signatureHex, 'valid_signature');
              verifiedMessage = message;
              return true;
            },
      );

      await verifier.verify(
        subjectDid: subjectDid,
        device: _device(
          binding: expectedBinding,
          bindingSignature: 'valid_signature',
        ),
      );

      expect(
        utf8.decode(verifiedMessage!),
        '{"device_id":"msgdev_bob","messenger_identity_key":"bob_identity",'
        '"signed_pre_key":"bob_signed_pre_key","signed_pre_key_id":42,'
        '"subject_did":"did:elix:bob",'
        '"type":"io.trisaura.messengerDeviceBinding","version":1}',
      );
    },
  );

  test(
    'rejects a relay-substituted binding before signature verification',
    () async {
      var signatureChecked = false;
      final verifier = DidMessengerDeviceBindingVerifier(
        resolveVerificationKey: (_) async => const MessengerDidVerificationKey(
          publicKeyHex: 'identity_public_key',
          algorithm: 'ed25519',
        ),
        verifySignature:
            ({required key, required message, required signatureHex}) async {
              signatureChecked = true;
              return true;
            },
      );

      await expectLater(
        verifier.verify(
          subjectDid: subjectDid,
          device: _device(
            binding: {...expectedBinding, 'messenger_identity_key': 'mallory'},
            bindingSignature: 'valid_signature',
          ),
        ),
        throwsA(
          isA<MessengerDeviceBindingInvalid>().having(
            (error) => error.reason,
            'reason',
            'binding_mismatch',
          ),
        ),
      );
      expect(signatureChecked, isFalse);
    },
  );

  test(
    'fails closed when the DID key is unavailable or signature is invalid',
    () async {
      final missingKeyVerifier = DidMessengerDeviceBindingVerifier(
        resolveVerificationKey: (_) async => null,
      );
      await expectLater(
        missingKeyVerifier.verify(
          subjectDid: subjectDid,
          device: _device(
            binding: expectedBinding,
            bindingSignature: 'signature',
          ),
        ),
        throwsA(
          isA<MessengerDeviceBindingInvalid>().having(
            (error) => error.reason,
            'reason',
            'verification_key_unavailable',
          ),
        ),
      );

      final invalidSignatureVerifier = DidMessengerDeviceBindingVerifier(
        resolveVerificationKey: (_) async => const MessengerDidVerificationKey(
          publicKeyHex: 'identity_public_key',
          algorithm: 'ed25519',
        ),
        verifySignature:
            ({required key, required message, required signatureHex}) async =>
                false,
      );
      await expectLater(
        invalidSignatureVerifier.verify(
          subjectDid: subjectDid,
          device: _device(
            binding: expectedBinding,
            bindingSignature: 'invalid_signature',
          ),
        ),
        throwsA(
          isA<MessengerDeviceBindingInvalid>().having(
            (error) => error.reason,
            'reason',
            'invalid_signature',
          ),
        ),
      );
    },
  );
}

MessengerPreKeyBundleDevice _device({
  required Map<String, Object?> binding,
  required String bindingSignature,
}) {
  return MessengerPreKeyBundleDevice(
    deviceId: 'msgdev_bob',
    messengerIdentityKey: 'bob_identity',
    signedPreKeyId: 42,
    signedPreKey: 'bob_signed_pre_key',
    signedPreKeySignature: 'bob_signed_pre_key_signature',
    oneTimePreKeyId: 1001,
    oneTimePreKey: 'bob_one_time_pre_key',
    binding: binding,
    bindingSignature: bindingSignature,
  );
}
