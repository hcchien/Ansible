import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';

import 'package:http/http.dart' as http;

import 'canonical_identity_store.dart';
import 'identity_anchor_service.dart';
import 'p256_jose.dart';
import 'wallet_credential_verifier.dart';
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
    request.validateRecipient();
    // Consent names one recipient; never follow a redirect with the VP.
    final outbound = http.Request('POST', request.responseUri)
      ..followRedirects = false
      ..headers['content-type'] = 'application/x-www-form-urlencoded'
      ..bodyFields = {
        'vp_token': jsonEncode(verifiablePresentation),
        'presentation_submission': jsonEncode(request.presentationSubmission()),
        if (request.state != null) 'state': request.state!,
      };
    final response = await _client.send(outbound).timeout(timeout);
    await response.stream.drain<void>().timeout(timeout);

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
    Set<String> trustedIssuers = const {'did:web:issuer.elix.cool'},
  }) {
    final verifier = WalletCredentialVerifier(
      client: httpClient,
      trustedIssuers: trustedIssuers,
    );
    return Oid4vpPresentationService(
      presentationService: VcPresentationService(
        walletRepository: walletRepository,
        trustedIssuers: trustedIssuers,
        proofVerifier: const SyntacticDataIntegrityProofVerifier(),
        statusResolver: verifier.status,
        cryptographicVerifier: verifier.verify,
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
    final prepared = await prepare(
      holderDid: holderDid,
      request: request,
      now: now,
    );
    return approvePrepared(prepared, now: now);
  }

  Future<PreparedOid4vpPresentation> prepare({
    required String holderDid,
    required Oid4vpAuthorizationRequest request,
    required DateTime now,
  }) async {
    request.validateRecipient();
    final binding = await presentationService.identityBinding(holderDid);
    final envelope = await presentationService.createForVerifierRequest(
      holderDid: holderDid,
      audience: request.audience,
      nonce: request.nonce,
      credentialType: request.requiredCredentialType,
      requiredClaimValues: request.requiredClaimValues,
      now: now,
      recordPresentation: false,
      sign: false,
    );
    if (envelope == null) {
      throw const Oid4vpSubmissionException(
        'no_matching_credential',
        'No verified, active matching credential is available.',
      );
    }
    return PreparedOid4vpPresentation._(
      this,
      holderDid,
      request,
      envelope.credentialId,
      jsonEncode(envelope.verifiablePresentation),
      now,
      binding,
    );
  }

  Future<Oid4vpSubmissionResult> approvePrepared(
    PreparedOid4vpPresentation prepared, {
    required DateTime now,
  }) async {
    if (prepared._owner != this ||
        prepared._used ||
        now.isBefore(prepared._created) ||
        now.difference(prepared._created) > const Duration(minutes: 5)) {
      throw const Oid4vpSubmissionException(
        'consent_expired',
        'Scan and review the request again.',
      );
    }
    prepared._used = true;
    final request = prepared.request;
    // Revalidate status and the exact selected credential; never silently select
    // a different credential after the user has reviewed the disclosure.
    final current = await presentationService.createForVerifierRequest(
      holderDid: prepared.holderDid,
      audience: request.audience,
      nonce: request.nonce,
      credentialType: request.requiredCredentialType,
      requiredClaimValues: request.requiredClaimValues,
      credentialId: prepared.credentialId,
      now: now,
      recordPresentation: false,
      sign: false,
    );
    final unsigned = prepared.presentation;
    if (prepared._binding !=
        await presentationService.identityBinding(prepared.holderDid)) {
      throw const Oid4vpSubmissionException(
        'holder_key_changed',
        'Review the request again.',
      );
    }
    if (current == null ||
        credentialCanonicalJson(
              current.verifiablePresentation['verifiableCredential'],
            ) !=
            credentialCanonicalJson(unsigned['verifiableCredential']) ||
        (current.verifiablePresentation['proof'] as Map)['cryptosuite'] !=
            (unsigned['proof'] as Map)['cryptosuite']) {
      throw const Oid4vpSubmissionException(
        'credential_changed',
        'Credential changed. Review the request again.',
      );
    }
    final envelope = VcPresentationEnvelope(
      credentialId: prepared.credentialId,
      verifiablePresentation: await presentationService.signPrepared(unsigned),
    );

    if (prepared._binding !=
        await presentationService.identityBinding(prepared.holderDid)) {
      throw const Oid4vpSubmissionException(
        'holder_key_changed',
        'Review the request again.',
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
    } on Object {
      await _recordResult(
        envelope: envelope,
        request: request,
        result: WalletPresentationResult.failed,
        now: now,
      );
      throw Oid4vpSubmissionException(
        'direct_post_failed',
        'Verifier direct_post failed.',
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

class PreparedOid4vpPresentation {
  PreparedOid4vpPresentation._(
    this._owner,
    this.holderDid,
    this.request,
    this.credentialId,
    this._json,
    this._created,
    this._binding,
  );
  final Oid4vpPresentationService _owner;
  final String holderDid;
  final Oid4vpAuthorizationRequest request;
  final String credentialId;
  final String _json;
  final DateTime _created;
  final String? _binding;
  bool _used = false;
  Map<String, Object?> get presentation =>
      (jsonDecode(_json) as Map).cast<String, Object?>();
}

class LocalVpProofSigner implements VpProofSigner, ConfiguredVpProofSigner {
  LocalVpProofSigner({
    IdentityKey? identityKey,
    CanonicalIdentityStore? identityStore,
  }) : _identityStore = identityStore ?? const SecureCanonicalIdentityStore(),
       _key = identityKey ?? const ActiveIdentityKey();
  final IdentityKey _key;
  final CanonicalIdentityStore _identityStore;

  Future<CanonicalIdentity> _identity(String holderDid) async {
    final identity = await _identityStore.load();
    if (identity == null ||
        identity.did != holderDid ||
        identity.publicKeyHex != await _key.publicKeyHex() ||
        identity.signingAlgorithm != await _key.algorithm()) {
      throw const Oid4vpSubmissionException(
        'missing_holder_key',
        'Active Wallet identity does not match the presentation holder.',
      );
    }
    return identity;
  }

  @override
  Future<String> identityBinding(String holderDid) async {
    final identity = await _identity(holderDid);
    return '${identity.did}:${identity.signingAlgorithm}:${identity.publicKeyHex}';
  }

  @override
  Future<Map<String, Object?>> proofOptions(String holderDid) async {
    final identity = await _identity(holderDid);
    final suite = switch (identity.signingAlgorithm) {
      'p256-sha256' => 'ecdsa-jcs-2019',
      'ed25519' => 'eddsa-jcs-2022',
      _ => throw const Oid4vpSubmissionException(
        'unsupported_holder_key',
        'Unsupported signing algorithm.',
      ),
    };
    return {'cryptosuite': suite, 'verificationMethod': '$holderDid#identity'};
  }

  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    final holder = unsignedPresentation['holder'] as String;
    final identity = await _identity(holder);
    final options = await proofOptions(holder);
    if ((unsignedPresentation['proof'] as Map)['cryptosuite'] !=
        options['cryptosuite']) {
      throw const Oid4vpSubmissionException(
        'holder_key_changed',
        'Review the request again.',
      );
    }
    final signature = _hexToBytes(
      await _key.sign(dataIntegrityHashData(unsignedPresentation)),
    );
    // Native P-256 signs SHA-256(hashData), returning ASN.1 DER; Data Integrity
    // uses the fixed-width r||s signature encoding.
    final bytes = identity.signingAlgorithm == 'p256-sha256'
        ? ecdsaDerSignatureToJose(signature)
        : signature;
    if (bytes.length != 64) {
      throw const FormatException('invalid_signature_length');
    }
    return 'z${_base58BtcEncode(bytes)}';
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
