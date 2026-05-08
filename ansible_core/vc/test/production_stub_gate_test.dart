import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:test/test.dart';

void main() {
  const storage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'ansible_plc_private_key': '11' * 32,
    });
  });

  test('production signer rejects Rust development fallback outputs', () async {
    final signer = LexiconSignerImpl(secureStorage: storage);

    await expectLater(
      signer.sign(const {
        r'$type': 'io.trisaura.post',
        'text': 'public post',
        'createdAt': '2026-05-08T00:00:00.000Z',
      }, authorDid: 'did:plc:abcdefghijklmnop'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('development signing fallback'),
        ),
      ),
    );
  });

  test('development signer fallback requires explicit opt-in', () async {
    final signer = LexiconSignerImpl(
      secureStorage: storage,
      allowInsecureFallback: true,
    );

    final signed = await signer.sign(const {
      r'$type': 'io.trisaura.post',
      'text': 'public post',
      'createdAt': '2026-05-08T00:00:00.000Z',
    }, authorDid: 'did:plc:abcdefghijklmnop');

    expect(signed.cid, startsWith('bafydev'));
    expect(signed.commitSigHex, startsWith('devsig'));
  });
}
