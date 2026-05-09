import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:test/test.dart';

void main() {
  group('SchnorrSigningBridge', () {
    test('matches BIP-340 signing vector 0', () async {
      final bridge = SchnorrSigningBridge(auxRandHex: '00' * 32);

      final signature = await bridge.signEventId(
        privateKeyHex:
            '0000000000000000000000000000000000000000000000000000000000000003',
        eventIdHex:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );

      expect(
        signature,
        'e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215'
        '25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0',
      );
    });

    test('derives x-only public key from private key', () {
      expect(
        SchnorrSigningBridge.derivePublicKeyHex(
          '0000000000000000000000000000000000000000000000000000000000000003',
        ),
        'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9',
      );
    });
  });
}
