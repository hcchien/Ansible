import 'dart:convert';
import 'dart:typed_data';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import 'oid4vp_request.dart';
import 'vc_presentation_service.dart';

const _base58BtcAlphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

class Oid4vpSubmissionException implements Exception {
  const Oid4vpSubmissionException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'Oid4vpSubmissionException($code): $message';
}

class Oid4vpSubmissionResult {
  const Oid4vpSubmissionResult({
    required this.credentialId,
    required this.verifierAudience,
  });

  final String credentialId;
  final String verifierAudience;
}

abstract class Oid4vpPresentationApprover {
  Future<Oid4vpSubmissionResult> approve({
    required String holderDid,
    required Oid4vpAuthorizationRequest request,
    required DateTime now,
  });
}

class Oid4vpDirectPostClient {
  Oid4vpDirectPostClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<void> submit({
    required Oid4vpAuthorizationRequest request,
    required Map<String, Object?> verifiablePresentation,
  }) async {
    final response = await _client
        .post(
          request.responseUri,
          headers: const {'content-type': 'application/x-www-form-urlencoded'},
          body: {
            'vp_token': jsonEncode(verifiablePresentation),
            'presentation_submission': jsonEncode(
              request.presentationSubmission(),
            ),
            if (request.state != null) 'state': request.state!,
          },
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Oid4vpSubmissionException(
        'direct_post_failed',
        'Verifier rejected the VP direct_post response.',
        statusCode: response.statusCode,
      );
    }
  }
}

class Oid4vpPresentationService implements Oid4vpPresentationApprover {
  Oid4vpPresentationService({
    required this.presentationService,
    required this.directPostClient,
  });

  factory Oid4vpPresentationService.forWallet({
    required WalletRepository walletRepository,
    http.Client? httpClient,
    Set<String> trustedIssuers = const {'did:web:issuer.trisaura.io'},
  }) {
    return Oid4vpPresentationService(
      presentationService: VcPresentationService(
        walletRepository: walletRepository,
        trustedIssuers: trustedIssuers,
        proofVerifier: const SyntacticDataIntegrityProofVerifier(),
        statusResolver: (_) async => CredentialStatus.active,
        proofSigner: LocalVpProofSigner(),
      ),
      directPostClient: Oid4vpDirectPostClient(client: httpClient),
    );
  }

  final VcPresentationService presentationService;
  final Oid4vpDirectPostClient directPostClient;

  @override
  Future<Oid4vpSubmissionResult> approve({
    required String holderDid,
    required Oid4vpAuthorizationRequest request,
    required DateTime now,
  }) async {
    final envelope = await presentationService.createForVerifierRequest(
      holderDid: holderDid,
      audience: request.audience,
      nonce: request.nonce,
      now: now,
      recordPresentation: false,
    );
    if (envelope == null) {
      throw const Oid4vpSubmissionException(
        'no_matching_credential',
        'No active matching credential is available in this Wallet.',
      );
    }

    try {
      await directPostClient.submit(
        request: request,
        verifiablePresentation: envelope.verifiablePresentation,
      );
    } on Oid4vpSubmissionException {
      await _recordResult(
        envelope: envelope,
        request: request,
        result: WalletPresentationResult.failed,
        now: now,
      );
      rethrow;
    } on Object catch (error) {
      await _recordResult(
        envelope: envelope,
        request: request,
        result: WalletPresentationResult.failed,
        now: now,
      );
      throw Oid4vpSubmissionException(
        'direct_post_failed',
        'Verifier direct_post failed: $error',
      );
    }

    await _recordResult(
      envelope: envelope,
      request: request,
      result: WalletPresentationResult.approved,
      now: now,
    );
    return Oid4vpSubmissionResult(
      credentialId: envelope.credentialId,
      verifierAudience: request.audience,
    );
  }

  Future<void> _recordResult({
    required VcPresentationEnvelope envelope,
    required Oid4vpAuthorizationRequest request,
    required WalletPresentationResult result,
    required DateTime now,
  }) {
    return presentationService.recordPresentationResult(
      credentialId: envelope.credentialId,
      audience: request.audience,
      nonce: request.nonce,
      result: result,
      now: now,
    );
  }
}

class SyntacticDataIntegrityProofVerifier implements ProofVerifier {
  const SyntacticDataIntegrityProofVerifier();

  @override
  bool verifyCredentialProof(TrisAuraCredential credential) {
    final proof = credential.proof;
    if (proof == null) return false;
    return proof['type'] == 'DataIntegrityProof' &&
        proof['cryptosuite'] == 'eddsa-jcs-2022' &&
        proof['proofPurpose'] == 'assertionMethod' &&
        proof['proofValue'] is String &&
        (proof['proofValue'] as String).startsWith('z');
  }
}

class LocalVpProofSigner implements VpProofSigner {
  LocalVpProofSigner({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _plcPrivateKey = 'ansible_plc_private_key';
  static const _legacyPrivateKey = 'ansible_did_private_key';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    final privateKeyHex =
        await _secureStorage.read(key: _plcPrivateKey) ??
        await _secureStorage.read(key: _legacyPrivateKey);
    if (privateKeyHex == null || privateKeyHex.isEmpty) {
      throw const Oid4vpSubmissionException(
        'missing_holder_key',
        'No local Wallet signing key is available.',
      );
    }

    try {
      final signatureHex = await RustLib.instance.apiSignCommit(
        cborBytes: Uint8List.fromList(utf8.encode(canonicalPayload)),
        privateKeyHex: privateKeyHex,
      );
      return dataIntegrityProofValueFromEd25519SignatureHex(signatureHex);
    } on UnimplementedError {
      if (!AppEnvironment.allowInsecureSigningFallback) {
        rethrow;
      }
      return 'zinsecuredevvpsig${canonicalPayload.length}';
    }
  }
}

String dataIntegrityProofValueFromEd25519SignatureHex(String signatureHex) {
  if (signatureHex.startsWith('z')) return signatureHex;
  final bytes = _hexToBytes(signatureHex);
  return 'z${_base58BtcEncode(bytes)}';
}

List<int> _hexToBytes(String hex) {
  final normalized = hex.trim();
  if (normalized.length.isOdd) {
    throw FormatException('Invalid hex signature length: $hex');
  }
  final out = <int>[];
  for (var i = 0; i < normalized.length; i += 2) {
    final byte = int.tryParse(normalized.substring(i, i + 2), radix: 16);
    if (byte == null) {
      throw FormatException('Invalid hex signature: $hex');
    }
    out.add(byte);
  }
  return out;
}

String _base58BtcEncode(List<int> data) {
  if (data.isEmpty) return '';

  var zeroes = 0;
  while (zeroes < data.length && data[zeroes] == 0) {
    zeroes += 1;
  }

  var value = BigInt.zero;
  for (final byte in data) {
    value = (value << 8) | BigInt.from(byte);
  }

  final chars = <String>[];
  final base = BigInt.from(58);
  while (value > BigInt.zero) {
    final mod = value % base;
    chars.add(_base58BtcAlphabet[mod.toInt()]);
    value = value ~/ base;
  }
  for (var i = 0; i < zeroes; i += 1) {
    chars.add(_base58BtcAlphabet[0]);
  }
  return chars.reversed.join();
}
