import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('elix/hardware_identity_key');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'board content agreement uses a purpose-separated hardware alias',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'generateAgreement':
                return <String, Object?>{
                  'public_key_hex': '04${'11' * 64}',
                  'custody': 'hardware',
                  'hardware_security_level': 'secure_enclave',
                };
              case 'deriveAgreement':
                return Uint8List.fromList(List<int>.filled(32, 7));
              case 'deleteAgreement':
                return null;
            }
            throw PlatformException(code: 'unexpected_method');
          });

      final key = HardwarePurposeAgreementKey(boardId: 'board-a');
      final publicKey = await key.generate();
      final secret = await key.derive('04${'22' * 64}');
      await key.delete();

      expect(publicKey.custody, IdentityKeyCustody.hardware);
      expect(secret, hasLength(32));
      expect(
        calls.map((call) => call.arguments['alias']),
        everyElement(
          startsWith('${HardwareKeyPurpose.boardContentKeyAgreement.alias}.'),
        ),
      );
      expect(
        HardwareKeyPurpose.boardContentKeyAgreement.alias,
        isNot(HardwareKeyPurpose.boardDeviceAuthorization.alias),
      );
    },
  );

  test(
    'rejects reduced-trust agreement key in private-board policy layer',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => <String, Object?>{
              'public_key_hex': '04${'33' * 64}',
              'custody': 'reduced_trust',
              'hardware_security_level': 'software_keystore',
            },
          );

      expect(
        HardwarePurposeAgreementKey(boardId: 'board-a').generate,
        throwsA(isA<StateError>()),
      );
    },
  );

  test('different boards use unlinkable hardware key aliases', () async {
    final aliases = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          aliases.add(call.arguments['alias'] as String);
          return <String, Object?>{
            'public_key_hex': '04${'44' * 64}',
            'custody': 'hardware',
          };
        });

    await HardwarePurposeAgreementKey(boardId: 'board-a').generate();
    await HardwarePurposeAgreementKey(boardId: 'board-b').generate();

    expect(aliases[0], isNot(aliases[1]));
    expect(aliases, everyElement(isNot(contains('board-a'))));
    expect(aliases, everyElement(isNot(contains('board-b'))));
  });

  test('board holder signing keys are hardware-only and unlinkable', () async {
    final aliases = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          aliases.add(call.arguments['alias'] as String);
          if (call.method == 'sign') {
            return <String, Object?>{'signature_hex': '30${'55' * 70}'};
          }
          return <String, Object?>{
            'public_key_hex': '04${'44' * 64}',
            'custody': 'hardware',
            'hardware_security_level': 'strongbox',
          };
        });

    final first = HardwareScopedPurposeKey(
      HardwareKeyPurpose.boardHolderBinding,
      context: 'board-a',
    );
    final second = HardwareScopedPurposeKey(
      HardwareKeyPurpose.boardHolderBinding,
      context: 'board-b',
    );
    await first.generate();
    await first.sign(const [1, 2, 3]);
    await second.generate();

    expect(aliases[0], aliases[1]);
    expect(aliases[0], isNot(aliases[2]));
    expect(aliases, everyElement(isNot(contains('board-a'))));
    expect(aliases, everyElement(isNot(contains('board-b'))));
    expect(
      aliases,
      everyElement(
        startsWith('${HardwareKeyPurpose.boardHolderBinding.alias}.'),
      ),
    );
  });

  test('board holder signing refuses reduced-trust custody', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => <String, Object?>{
            'public_key_hex': '04${'66' * 64}',
            'custody': 'reduced_trust',
          },
        );

    expect(
      HardwareScopedPurposeKey(
        HardwareKeyPurpose.boardHolderBinding,
        context: 'board-a',
      ).generate,
      throwsA(isA<StateError>()),
    );
  });
}
