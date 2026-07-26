import 'dart:convert';

import 'package:ansible_store/ansible_store.dart' show Ed25519Keys;
import 'package:ansible_vc/ansible_vc.dart' show VpBuilder;
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/protocol.dart';

class HumanAssuranceProfile {
  const HumanAssuranceProfile({
    required this.identityControl,
    required this.humanEvidence,
    required this.uniqueness,
    required this.methodClass,
  });

  final String identityControl;
  final String humanEvidence;
  final String uniqueness;
  final String methodClass;

  String get compatibilityTier {
    if (humanEvidence == 'natural_person' && uniqueness == 'strong') {
      return 'unique_human';
    }
    if (humanEvidence == 'natural_person') return 'humanity_limited';
    if (humanEvidence == 'liveness') return 'humanity_limited';
    if (humanEvidence == 'legacy_verified') return 'verified_human';
    return 'basic';
  }
}

/// Portable, trustless verified-human (federation trust design): trust the
/// ISSUER, not the relay. A relay serves the issuer-signed VC that earned a
/// DID's tier (`GET /api/v1/identity/attestation/:did`); this service
/// re-verifies the issuer's Ed25519 proof against a PINNED issuer key before
/// any tier is believed. A missing, unverifiable, expired, or
/// wrong-subject attestation yields null — the caller stays at `basic`
/// (fail closed), matching the app-side fix that stopped trusting
/// peer-asserted tiers (2c5f91d).
///
/// Canonicalization is the repo-wide invariant: Dart's
/// `VpBuilder.canonicalPayload` (deep key sort + compact JSON) is
/// byte-identical to the relay's `deep_sort_keys |> Jason.encode!` — the VC
/// is verified over exactly the bytes the issuer signed.
class IssuerAttestationService {
  IssuerAttestationService({
    required String relayBaseUrl,
    String? issuerBaseUrl,
    String? pinnedIssuerKeyHex,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _relayBaseUri = Uri.parse(relayBaseUrl),
       _issuerBaseUri = Uri.parse(
         issuerBaseUrl ?? AppEnvironment.issuerBaseUrl,
       ),
       _pinnedIssuerKeyHex = pinnedIssuerKeyHex,
       _client = client ?? http.Client(),
       _now = now ?? (() => DateTime.now().toUtc());

  final Uri _relayBaseUri;
  final Uri _issuerBaseUri;

  /// Hard pin override; when null the key is resolved once from the issuer's
  /// `did:web` document over HTTPS and cached for the process lifetime.
  final String? _pinnedIssuerKeyHex;
  final http.Client _client;
  final Duration timeout;
  final DateTime Function() _now;

  static const _recognizedCredentialTypes = {
    'TrisAuraHumanityCredential',
    'EmailCredential',
  };

  String? _issuerKeyHexCache;
  final Map<String, HumanAssuranceProfile?> _assuranceCache = {};

  /// The issuer-attested reputation tier for [did], or null when no
  /// verifiable attestation exists (caller treats as `basic`). Verified
  /// results — including definitive negatives (404, failed proof) — are
  /// cached for the process lifetime; transport errors are NOT cached so
  /// the next batch retries. Ingest calls this per author, so repeats must
  /// be cheap.
  Future<String?> verifiedTierFor(String did) async {
    final assurance = await verifiedAssuranceFor(did);
    return assurance?.compatibilityTier;
  }

  /// Returns orthogonal assurance dimensions. `identityControl` describes the
  /// DID proof on this presentation; passkey UV is a separate operation proof
  /// and is never inferred from video or personhood credentials.
  Future<HumanAssuranceProfile?> verifiedAssuranceFor(String did) async {
    if (_assuranceCache.containsKey(did)) return _assuranceCache[did];

    final http.Response response;
    try {
      response = await _client
          .get(
            _endpoint(
              _relayBaseUri,
              '/api/v1/identity/attestation/${Uri.encodeComponent(did)}',
            ),
            headers: AnsibleProtocol.headers,
          )
          .timeout(timeout);
    } catch (_) {
      return null; // transport error — fail closed, retry later
    }

    HumanAssuranceProfile? assurance;
    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body);
        final vc = decoded is Map ? decoded['vc'] : null;
        if (vc is Map) {
          assurance = await _verifyVc(did, vc.cast<String, Object?>());
        }
      } catch (_) {
        assurance = null;
      }
    }

    // 200-with-bad-proof and 404 are both definitive negatives — cache them.
    _assuranceCache[did] = assurance;
    return assurance;
  }

  /// Verifies subject, issuer, validity window, and the issuer's Ed25519
  /// proof; returns locally-derived assurance dimensions, or null.
  Future<HumanAssuranceProfile?> _verifyVc(
    String did,
    Map<String, Object?> vc,
  ) async {
    // Subject must be the DID whose assurance this would set.
    final subject = vc['credentialSubject'];
    if (subject is! Map || subject['id'] != did) return null;

    // The credential must be issued by OUR pinned issuer.
    final expectedIssuerDid = 'did:web:${_issuerBaseUri.host}';
    if (vc['issuer'] != expectedIssuerDid) return null;

    // Type must map to an assurance profile we recognize.
    final types = vc['type'];
    if (types is! List) return null;
    final credentialType = types.whereType<String>().firstWhere(
      _recognizedCredentialTypes.contains,
      orElse: () => '',
    );
    if (credentialType.isEmpty) return null;

    // Validity window.
    final notAfter = DateTime.tryParse(vc['validUntil'] as String? ?? '');
    final notBefore = DateTime.tryParse(vc['validFrom'] as String? ?? '');
    final now = _now();
    if (notAfter == null || !now.isBefore(notAfter)) return null;
    if (notBefore != null && now.isBefore(notBefore)) return null;

    // Issuer Ed25519 proof over the canonical (deep-sorted, compact) body.
    final proof = vc['proof'];
    if (proof is! Map) return null;
    final proofValue = proof['proofValue'];
    if (proofValue is! String || proofValue.isEmpty) return null;

    final issuerKeyHex = await _issuerPublicKeyHex();
    if (issuerKeyHex == null) return null;

    final withoutProof = Map<String, Object?>.from(vc)..remove('proof');
    final canonical = VpBuilder.canonicalPayload(withoutProof);

    // Pure-Dart Ed25519 (same suite the device-attestation path uses), so
    // verification needs no Rust bridge and runs identically in tests.
    final bool valid;
    try {
      valid = await Ed25519Keys.verify(
        publicKeyHex: issuerKeyHex,
        message: utf8.encode(canonical),
        sigHex: proofValue,
      );
    } catch (_) {
      return null; // malformed key/signature hex — fail closed
    }
    if (!valid) return null;

    return _assuranceForCredential(credentialType, subject);
  }

  /// Mirrors Relay `ReputationTier.for_credential/2`. Legacy humanity VCs
  /// remain `verified_human`; new issuer-signed assurance claims distinguish
  /// limited liveness from strong privacy-preserving uniqueness.
  static HumanAssuranceProfile _assuranceForCredential(
    String type,
    Map subject,
  ) {
    const none = HumanAssuranceProfile(
      identityControl: 'did_key',
      humanEvidence: 'none',
      uniqueness: 'unknown',
      methodClass: 'none',
    );
    if (type == 'EmailCredential') return none;
    if (type != 'TrisAuraHumanityCredential' ||
        subject['humanVerified'] != true) {
      return none;
    }

    final human = subject['humanAssurance'];
    final uniqueness = subject['uniquenessAssurance'];
    if (human == 'verified' && uniqueness == 'strong') {
      return HumanAssuranceProfile(
        identityControl: 'did_key',
        humanEvidence: 'natural_person',
        uniqueness: 'strong',
        methodClass:
            subject['verificationMethodClass'] as String? ?? 'unspecified',
      );
    }
    if (human == 'verified' &&
        (uniqueness == 'limited' || uniqueness == 'unknown')) {
      return HumanAssuranceProfile(
        identityControl: 'did_key',
        humanEvidence: 'natural_person',
        uniqueness: uniqueness as String,
        methodClass:
            subject['verificationMethodClass'] as String? ?? 'unspecified',
      );
    }
    if (human == 'liveness' &&
        (uniqueness == 'limited' || uniqueness == 'unknown')) {
      return HumanAssuranceProfile(
        identityControl: 'did_key',
        humanEvidence: 'liveness',
        uniqueness: uniqueness as String,
        methodClass:
            subject['verificationMethodClass'] as String? ?? 'liveness',
      );
    }
    if (human == null && uniqueness == null) {
      return const HumanAssuranceProfile(
        identityControl: 'did_key',
        humanEvidence: 'legacy_verified',
        uniqueness: 'unknown',
        methodClass: 'legacy',
      );
    }
    return none;
  }

  /// The pinned issuer Ed25519 key: the explicit pin when configured,
  /// otherwise resolved once from `https://<issuer>/.well-known/did.json`
  /// (certificate-authenticated did:web resolution) and cached.
  Future<String?> _issuerPublicKeyHex() async {
    final pinned = _pinnedIssuerKeyHex;
    if (pinned != null && pinned.isNotEmpty) return pinned;
    if (_issuerKeyHexCache != null) return _issuerKeyHexCache;

    try {
      final response = await _client
          .get(_endpoint(_issuerBaseUri, '/.well-known/did.json'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final document = jsonDecode(response.body);
      if (document is! Map) return null;
      final methods = document['verificationMethod'];
      if (methods is! List || methods.isEmpty) return null;
      final multibase = (methods.first as Map)['publicKeyMultibase'];
      if (multibase is! String) return null;
      final hex = decodeEd25519Multibase(multibase);
      _issuerKeyHexCache = hex;
      return hex;
    } catch (_) {
      return null;
    }
  }

  Uri _endpoint(Uri base, String path) {
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path');
  }

  void close() => _client.close();
}

const _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Decodes a multibase (`z` base58btc) Ed25519 public key — the
/// `publicKeyMultibase` form in a did:web / did:key document
/// (`0xed 0x01 || 32-byte key`) — to lowercase hex. Returns null on any
/// malformed input (never throws — feeds a fail-closed path). Inverse of
/// `encodeDidKeyEd25519` in ansible_store.
String? decodeEd25519Multibase(String multibase) {
  if (!multibase.startsWith('z') || multibase.length < 2) return null;
  final encoded = multibase.substring(1);

  var value = BigInt.zero;
  for (final rune in encoded.runes) {
    final index = _base58Alphabet.indexOf(String.fromCharCode(rune));
    if (index < 0) return null;
    value = value * BigInt.from(58) + BigInt.from(index);
  }

  var bytes = <int>[];
  while (value > BigInt.zero) {
    bytes.insert(0, (value % BigInt.from(256)).toInt());
    value = value ~/ BigInt.from(256);
  }
  // Leading '1's encode leading zero bytes.
  for (final rune in encoded.runes) {
    if (String.fromCharCode(rune) != '1') break;
    bytes.insert(0, 0);
  }

  // Expect the ed25519-pub multicodec prefix + 32 key bytes.
  if (bytes.length != 34 || bytes[0] != 0xed || bytes[1] != 0x01) return null;
  return bytes
      .sublist(2)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
