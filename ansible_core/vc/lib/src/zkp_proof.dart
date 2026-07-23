import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'passport_data.dart';
import 'swoir_zkpassport_backend.dart';

// ZkpProof — the proof artifact uploaded to the Relay during Phase 1.
class ZkpProof {
  /// Proof backend used by the pinned ZKPassport circuit manifest.
  final String backend;

  /// JSON ZKPassport proof envelope accepted by the Issuer verifier.
  final String proofHex;

  /// Hex-encoded 32-byte anti-Sybil nullifier (public output of the circuit)
  final String nullifierHex;

  /// SHA-256 digest of the complete proof envelope for diagnostics.
  final String vkHash;

  /// Server-verifiable commitment for the passport holder's national ID.
  final String nationalIdHash;

  /// Server-verifiable commitment for the passport document number.
  final String passportNumberHash;

  const ZkpProof({
    required this.backend,
    required this.proofHex,
    required this.nullifierHex,
    required this.vkHash,
    required this.nationalIdHash,
    required this.passportNumberHash,
  });

  /// Circuit version string sent to the Relay as `zkp_circuit_version`.
  static const kCircuitVersion = '0.20.0';

  Map<String, Object?> toRelayJson() => {
    'zkp_proof': proofHex,
    'zkp_circuit_version': kCircuitVersion,
    'verification_key_hash': 'sha256:$vkHash',
    'nullifier': nullifierHex,
  };
}

class ZkpChallengeBinding {
  const ZkpChallengeBinding({
    required this.challengeId,
    required this.nonce,
    required this.did,
    required this.issuer,
    required this.scope,
  });

  final String challengeId;
  final String nonce;
  final String did;
  final String issuer;
  final String scope;
}

abstract class ZkpProver {
  /// Generate challenge-bound ZKPassport proofs from ephemeral chip data.
  Future<ZkpProof> prove({
    required PassportData passport,
    required ZkpChallengeBinding challenge,
  });
}

enum ZkpProverStage { planning, initializingSrs, preparing, proving, verifying }

class ZkpProverProgress {
  const ZkpProverProgress({
    required this.stage,
    this.circuitName,
    this.circuitIndex = 0,
    this.circuitCount = 0,
    required this.elapsed,
  });

  final ZkpProverStage stage;
  final String? circuitName;
  final int circuitIndex;
  final int circuitCount;
  final Duration elapsed;
}

typedef ZkpProverProgressCallback = void Function(ZkpProverProgress progress);

abstract class ZkpSrsProvider {
  Future<String> acquire();

  Future<void> release(String path);
}

class MissingZkpSrsProvider implements ZkpSrsProvider {
  const MissingZkpSrsProvider();

  @override
  Future<String> acquire() =>
      Future.error(StateError('No ZKPassport SRS provider is configured.'));

  @override
  Future<void> release(String path) async {}
}

class ZkpProverException implements Exception {
  const ZkpProverException(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => 'ZkpProverException($stage)';
}

/// Embedded ZKPassport prover backed by the native iOS Swoir runtime.
class ZkpProverImpl implements ZkpProver {
  const ZkpProverImpl({
    this.backend = const SwoirZkPassportBackend(),
    this.srsProvider = const MissingZkpSrsProvider(),
    this.onProgress,
  });

  final SwoirZkPassportBackend backend;
  final ZkpSrsProvider srsProvider;
  final ZkpProverProgressCallback? onProgress;

  @override
  Future<ZkpProof> prove({
    required PassportData passport,
    required ZkpChallengeBinding challenge,
  }) async {
    final stopwatch = Stopwatch()..start();
    void report(
      ZkpProverStage stage, {
      String? circuitName,
      int circuitIndex = 0,
      int circuitCount = 0,
    }) {
      onProgress?.call(
        ZkpProverProgress(
          stage: stage,
          circuitName: circuitName,
          circuitIndex: circuitIndex,
          circuitCount: circuitCount,
          elapsed: stopwatch.elapsed,
        ),
      );
    }

    report(ZkpProverStage.planning);
    final runtime = await rootBundle.loadString('assets/zkpassport/runtime.js');
    final bindingPayload = jsonEncode({
      'challenge_id': challenge.challengeId,
      'challenge_nonce': challenge.nonce,
      'did': challenge.did,
      'issuer': challenge.issuer,
      'scope': challenge.scope,
    });
    final challengeBinding = sha256
        .convert(utf8.encode(bindingPayload))
        .toString();
    final random = Random.secure();
    final saltBytes = Uint8List.fromList(
      List<int>.generate(31, (_) => random.nextInt(256)),
    );
    final salt = _bytesToBigInt(saltBytes);
    late final Map<String, Object?> plan;
    try {
      plan = await backend.createProofPlan(
        runtimeJavaScript: runtime,
        request: {
          'version': ZkpProof.kCircuitVersion,
          'salt': salt.toString(),
          'dg1': passport.dg1Bytes.toList(growable: false),
          'sod': passport.sodBytes.toList(growable: false),
          'issuer': challenge.issuer,
          'scope': challenge.scope,
          'challenge_binding': challengeBinding,
        },
      );
    } on Object catch (error) {
      throw ZkpProverException('plan', error);
    }
    if (plan['version'] != ZkpProof.kCircuitVersion) {
      throw StateError('ZKPassport circuit manifest version mismatch.');
    }
    final circuits = (plan['circuits'] as List<Object?>?) ?? const [];
    if (circuits.length != 5) {
      throw StateError('ZKPassport proof plan is incomplete.');
    }
    final proofResults = <Map<String, Object?>>[];
    String? srsPath;
    try {
      try {
        srsPath = await srsProvider.acquire();
      } on Object catch (error) {
        throw ZkpProverException('srs-download', error);
      }
      final circuitSizes = circuits
          .map(
            (raw) =>
                Map<String, Object?>.from(
                      raw! as Map<Object?, Object?>,
                    )['size']!
                    as int,
          )
          .toList(growable: false);
      final maximumCircuitSize = circuitSizes.reduce(max);
      report(ZkpProverStage.initializingSrs);
      try {
        await backend.initializeSrs(
          circuitSize: maximumCircuitSize,
          srsPath: srsPath,
        );
      } on Object catch (error) {
        throw ZkpProverException('srs-initialize', error);
      }
      for (var index = 0; index < circuits.length; index += 1) {
        final rawCircuit = circuits[index];
        final circuit = Map<String, Object?>.from(
          rawCircuit! as Map<Object?, Object?>,
        );
        final manifest = Map<String, Object?>.from(
          circuit['manifest']! as Map<Object?, Object?>,
        );
        final inputs = Map<String, Object?>.from(
          circuit['inputs']! as Map<Object?, Object?>,
        );
        final verificationKey = base64Decode(circuit['vkey']! as String);
        final name = circuit['name']! as String;
        late final String circuitId;
        report(
          ZkpProverStage.preparing,
          circuitName: name,
          circuitIndex: index + 1,
          circuitCount: circuits.length,
        );
        try {
          circuitId = await backend.prepare(
            manifestJson: jsonEncode(manifest),
            circuitSize: circuitSizes[index],
          );
        } on Object catch (error) {
          throw ZkpProverException('prepare:$name', error);
        }
        late final Uint8List proof;
        report(
          ZkpProverStage.proving,
          circuitName: name,
          circuitIndex: index + 1,
          circuitCount: circuits.length,
        );
        try {
          proof = await backend.prove(
            circuitId: circuitId,
            inputs: inputs,
            verificationKey: verificationKey,
          );
        } on Object catch (error) {
          throw ZkpProverException('prove:$name', error);
        }
        late final bool locallyVerified;
        report(
          ZkpProverStage.verifying,
          circuitName: name,
          circuitIndex: index + 1,
          circuitCount: circuits.length,
        );
        try {
          locallyVerified = await backend.verify(
            circuitId: circuitId,
            proof: proof,
            verificationKey: verificationKey,
          );
        } on Object catch (error) {
          throw ZkpProverException('verify:$name', error);
        }
        if (!locallyVerified) {
          throw StateError(
            'A generated ZKPassport proof failed local verification.',
          );
        }
        proofResults.add({
          'proof': _hex(proof),
          'vkeyHash': circuit['vkey_hash'],
          'version': plan['version'],
          'name': circuit['name'],
        });
      }
    } finally {
      await backend.clear();
      final acquiredSrsPath = srsPath;
      if (acquiredSrsPath != null) {
        await srsProvider.release(acquiredSrsPath);
      }
    }
    final envelope = jsonEncode({
      'proofs': proofResults,
      'query_result': plan['query_result'],
    });
    final envelopeHash = sha256.convert(utf8.encode(envelope)).toString();
    return ZkpProof(
      backend: 'ultra_honk',
      proofHex: envelope,
      nullifierHex: '',
      vkHash: envelopeHash,
      // These values are deliberately not authoritative. The Issuer derives
      // private duplicate-prevention commitments from verified public inputs.
      nationalIdHash: 'issuer-derived-$envelopeHash',
      passportNumberHash: 'issuer-derived-$envelopeHash',
    );
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
