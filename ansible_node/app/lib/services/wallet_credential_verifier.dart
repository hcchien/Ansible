import 'dart:convert';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// The supported issuer profile: did:web, Ed25519 Data Integrity, and an
/// issuer-origin status endpoint. Unsupported or unavailable proofs fail closed.
class WalletCredentialVerifier {
  WalletCredentialVerifier({http.Client? client, required this.trustedIssuers})
    : _client = client ?? http.Client();
  final http.Client _client;
  final Set<String> trustedIssuers;

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const FormatException('verification_unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 10),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 262144) {
        throw const FormatException('verification_response_too_large');
      }
    }
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  Uri _issuerUri(String did) {
    if (!trustedIssuers.contains(did) || !did.startsWith('did:web:')) {
      throw const FormatException('untrusted_issuer');
    }
    final parts = did.substring(8).split(':').map(Uri.decodeComponent).toList();
    final uri = Uri.parse(
      'https://${parts.first}/${parts.length == 1 ? '.well-known/' : '${parts.skip(1).join('/')}/'}did.json',
    );
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('invalid_issuer');
    }
    return uri;
  }

  Future<bool> verify(TrisAuraCredential credential) async {
    try {
      final proof = credential.proof;
      if (proof == null ||
          proof['type'] != 'DataIntegrityProof' ||
          proof['cryptosuite'] != 'eddsa-jcs-2022' ||
          proof['proofPurpose'] != 'assertionMethod') {
        return false;
      }
      final doc = await _get(_issuerUri(credential.issuerDid));
      if (doc['id'] != credential.issuerDid) return false;
      final methodId = proof['verificationMethod'];
      if (methodId is! String ||
          !methodId.startsWith('${credential.issuerDid}#')) {
        return false;
      }
      String fullId(Object? id) => id is String && id.startsWith('#')
          ? '${credential.issuerDid}$id'
          : '$id';
      final assertions = doc['assertionMethod'];
      if (assertions is! List ||
          !assertions.any((v) => fullId(v is Map ? v['id'] : v) == methodId)) {
        return false;
      }
      final methods = [
        ...?doc['verificationMethod'] as List?,
        ...assertions.whereType<Map>(),
      ];
      final candidates = methods
          .whereType<Map>()
          .where((v) => fullId(v['id']) == methodId)
          .toList();
      if (candidates.length != 1 ||
          candidates.single['controller'] != credential.issuerDid) {
        return false;
      }
      final key = decodeBase58Multibase(
        candidates.single['publicKeyMultibase'] as String,
      );
      if (key.length != 34 || key[0] != 0xed || key[1] != 1) return false;
      final signature = decodeBase58Multibase(proof['proofValue'] as String);
      if (signature.length != 64) return false;
      return await Ed25519().verify(
        dataIntegrityHashData(credential.json),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(key.sublist(2), type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  Future<CredentialStatus> status(TrisAuraCredential credential) async {
    try {
      final issuer = _issuerUri(credential.issuerDid);
      if (credential.credentialStatus.length != 1) {
        return CredentialStatus.unknown;
      }
      final entry = credential.credentialStatus.single;
      if (entry['type'] != 'TrisAuraStatusEndpoint2024') {
        return CredentialStatus.unknown;
      }
      final uri = Uri.parse(entry['id'] as String);
      if (uri.scheme != 'https' ||
          uri.origin != issuer.origin ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.hasQuery ||
          !RegExp(r'^/api/v1/vc/status/[a-zA-Z0-9-]+$').hasMatch(uri.path)) {
        return CredentialStatus.unknown;
      }
      final result = await _get(uri);
      if (result['id'] != uri.pathSegments.last) {
        return CredentialStatus.unknown;
      }
      if (result['revoked'] == true || result['status'] == 'revoked') {
        return CredentialStatus.revoked;
      }
      return result['status'] == 'active' && result['revoked'] == false
          ? CredentialStatus.active
          : CredentialStatus.unknown;
    } on Object {
      return CredentialStatus.unknown;
    }
  }
}

/// JCS subset used by this issuer profile. Reject non-integral/unsafe numbers
/// rather than silently sign a different numeric representation across clients.
String credentialCanonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${credentialCanonicalJson(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(credentialCanonicalJson).join(',')}]';
  if (value is num && (value is! int || value.abs() > 9007199254740991)) {
    throw const FormatException('unsupported_canonical_number');
  }
  return jsonEncode(value);
}

List<int> dataIntegrityHashData(Map<String, Object?> document) {
  final body = {...document}..remove('proof');
  final options = Map<String, Object?>.from(document['proof'] as Map)
    ..remove('proofValue');
  options['@context'] = document['@context'];
  return [
    ...hash.sha256.convert(utf8.encode(credentialCanonicalJson(options))).bytes,
    ...hash.sha256.convert(utf8.encode(credentialCanonicalJson(body))).bytes,
  ];
}

List<int> decodeBase58Multibase(String input) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  if (!input.startsWith('z') || input.length > 256) {
    throw const FormatException('invalid_multibase');
  }
  final value = input.substring(1);
  var number = BigInt.zero;
  for (final code in value.codeUnits) {
    final digit = alphabet.indexOf(String.fromCharCode(code));
    if (digit < 0) throw const FormatException('invalid_base58');
    number = number * BigInt.from(58) + BigInt.from(digit);
  }
  final bytes = <int>[];
  while (number > BigInt.zero) {
    bytes.add((number & BigInt.from(255)).toInt());
    number >>= 8;
  }
  return [
    ...List.filled(value.split('').takeWhile((v) => v == '1').length, 0),
    ...bytes.reversed,
  ];
}
