import 'dart:convert';

import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('elix/zkpassport_prover');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards prepared inputs to the native Swoir backend', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'prepare' => 'circuit-1',
            'prove' => Uint8List.fromList([1, 2, 3]),
            'verify' => true,
            _ => null,
          };
        });
    const backend = SwoirZkPassportBackend();
    await backend.initializeSrs(
      circuitSize: 2048,
      srsPath: '/tmp/srs-21.local',
    );
    final circuit = await backend.prepare(
      manifestJson: '{"version":"0.20.0"}',
      circuitSize: 1024,
    );
    final proof = await backend.prove(
      circuitId: circuit,
      inputs: const {'challenge': 'nonce-bound'},
      verificationKey: Uint8List.fromList([4, 5]),
    );
    expect(
      await backend.verify(
        circuitId: circuit,
        proof: proof,
        verificationKey: Uint8List.fromList([4, 5]),
      ),
      isTrue,
    );
    expect(calls.map((call) => call.method), [
      'initialize_srs',
      'prepare',
      'prove',
      'verify',
    ]);
  });

  test('produces a complete challenge-bound five-proof envelope', () async {
    final calls = <MethodCall>[];
    Map<Object?, Object?>? planArguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'plan':
              planArguments = call.arguments as Map<Object?, Object?>;
              return <String, Object?>{
                'version': ZkpProof.kCircuitVersion,
                'query_result': {
                  'nationality': {
                    'disclose': {'result': 'TWN'},
                  },
                },
                'circuits': List<Map<String, Object?>>.generate(
                  5,
                  (index) => {
                    'name': 'circuit-$index',
                    'size': 100000 + (index * 1000),
                    'manifest': {'name': 'circuit-$index', 'bytecode': 'AA=='},
                    'inputs': {'witness': '$index'},
                    'vkey': base64Encode([index + 1]),
                    'vkey_hash': 'hash-$index',
                  },
                ),
              };
            case 'prepare':
              return 'prepared-${calls.where((item) => item.method == 'prepare').length}';
            case 'prove':
              return Uint8List.fromList([0xca, 0xfe]);
            case 'verify':
              return true;
            case 'clear':
              return null;
          }
          return null;
        });

    final srsProvider = _FakeZkpSrsProvider();
    final progress = <ZkpProverProgress>[];
    final proof =
        await ZkpProverImpl(
          srsProvider: srsProvider,
          onProgress: progress.add,
        ).prove(
          passport: const PassportData(
            documentNumber: '123456789',
            dateOfBirth: '720129',
            dateOfExpiry: '330613',
            nationality: 'TWN',
            dg1Bytes: [0x61, 0x01],
            sodBytes: [0x77, 0x01],
            passportSecret: 'not-uploaded',
            sodSignatureVerified: true,
            dataGroupHashesVerified: true,
          ),
          challenge: const ZkpChallengeBinding(
            challengeId: 'challenge-id',
            nonce: 'single-use-nonce',
            did: 'did:key:test',
            issuer: 'https://issuer-dev.elix.cool',
            scope: 'elix-passport-personhood-v1',
          ),
        );

    final envelope = jsonDecode(proof.proofHex) as Map<String, Object?>;
    expect((envelope['proofs'] as List<Object?>), hasLength(5));
    expect(calls.where((call) => call.method == 'prepare'), hasLength(5));
    expect(
      calls.where((call) => call.method == 'initialize_srs'),
      hasLength(1),
    );
    expect(calls.where((call) => call.method == 'prove'), hasLength(5));
    expect(calls.where((call) => call.method == 'verify'), hasLength(5));
    expect(calls.where((call) => call.method == 'clear'), hasLength(1));
    expect(srsProvider.acquisitions, 1);
    expect(srsProvider.releases, ['/tmp/srs-21.local']);
    final srsCall = calls.singleWhere(
      (call) => call.method == 'initialize_srs',
    );
    expect(
      (srsCall.arguments as Map<Object?, Object?>)['srs_path'],
      '/tmp/srs-21.local',
    );
    expect(
      (srsCall.arguments as Map<Object?, Object?>)['circuit_size'],
      104000,
    );
    expect(
      progress.where((item) => item.stage == ZkpProverStage.proving),
      hasLength(5),
    );

    final request = Map<Object?, Object?>.from(
      planArguments!['request']! as Map<Object?, Object?>,
    );
    expect(request['challenge_binding'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(request['scope'], 'elix-passport-personhood-v1');
    expect(request['dg1'], [0x61, 0x01]);
    expect(request['sod'], [0x77, 0x01]);
    expect(proof.proofHex, isNot(contains('123456789')));
    expect(proof.proofHex, isNot(contains('single-use-nonce')));
  });
}

class _FakeZkpSrsProvider implements ZkpSrsProvider {
  int acquisitions = 0;
  final List<String> releases = [];

  @override
  Future<String> acquire() async {
    acquisitions += 1;
    return '/tmp/srs-21.local';
  }

  @override
  Future<void> release(String path) async {
    releases.add(path);
  }
}
