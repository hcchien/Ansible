import 'dart:convert';
import 'dart:io';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'credential_payload_codec.dart';
import 'wallet_holder_key_service.dart';

class Oid4vciWalletException implements Exception {
  const Oid4vciWalletException(this.code, this.message, {this.statusCode});
  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'Oid4vciWalletException($code): $message';
}

class Oid4vciCredentialOffer {
  const Oid4vciCredentialOffer({
    required this.credentialIssuer,
    required this.configurationId,
    required this.preAuthorizedCode,
    required this.boardId,
  });

  final Uri credentialIssuer;
  final String configurationId;
  final String preAuthorizedCode;
  final String boardId;

  factory Oid4vciCredentialOffer.parse(Map<String, Object?> json) {
    final issuer = Uri.tryParse(json['credential_issuer'] as String? ?? '');
    final ids = json['credential_configuration_ids'];
    final grants = json['grants'];
    final preAuthorized = grants is Map
        ? grants['urn:ietf:params:oauth:grant-type:pre-authorized_code']
        : null;
    final code = preAuthorized is Map
        ? preAuthorized['pre-authorized_code']
        : null;
    final boardId = json['board_id'];
    if (issuer == null ||
        !issuer.hasAuthority ||
        issuer.scheme != 'https' ||
        ids is! List ||
        ids.length != 1 ||
        ids.first is! String ||
        code is! String ||
        code.isEmpty ||
        boardId is! String ||
        boardId.trim().isEmpty) {
      throw const Oid4vciWalletException(
        'invalid_offer',
        'Credential offer is malformed.',
      );
    }
    return Oid4vciCredentialOffer(
      credentialIssuer: issuer,
      configurationId: ids.first as String,
      preAuthorizedCode: code,
      boardId: boardId,
    );
  }
}

class Oid4vciWalletClient {
  Oid4vciWalletClient({
    required WalletRepository walletRepository,
    http.Client? httpClient,
    HolderBindingKey? holderKey,
    SecureCredentialPayloadCodec? payloadCodec,
    DateTime Function()? now,
  }) : _walletRepository = walletRepository,
       _http = httpClient ?? http.Client(),
       _holderKeyOverride = holderKey,
       _payloadCodec = payloadCodec ?? const SecureCredentialPayloadCodec(),
       _now = now ?? (() => DateTime.now().toUtc());

  final WalletRepository _walletRepository;
  final http.Client _http;
  final HolderBindingKey? _holderKeyOverride;
  final SecureCredentialPayloadCodec _payloadCodec;
  final DateTime Function() _now;

  Future<String> applyForMembership({
    required Uri credentialIssuer,
    required String boardId,
    String membershipClass = 'member',
  }) async {
    if (credentialIssuer.scheme != 'https' ||
        !credentialIssuer.path.startsWith('/tenants/')) {
      throw const Oid4vciWalletException(
        'invalid_issuer',
        'Membership applications require an HTTPS hosted issuer.',
      );
    }
    final nonceResponse = await _postJson(
      credentialIssuer.resolve('${credentialIssuer.path}/nonce'),
      const {},
    );
    final nonce = _requiredString(nonceResponse, 'c_nonce');
    if (boardId.trim().isEmpty) {
      throw const Oid4vciWalletException(
        'board_required',
        'Membership credentials must be bound to a board.',
      );
    }
    final holderKey = _holderKey(boardId);
    final proof = await _proofJwt(
      credentialIssuer.toString(),
      nonce,
      holderKey,
    );
    final holderDid = await _pairwiseDid(holderKey);
    final response = await _postJson(
      credentialIssuer.resolve('${credentialIssuer.path}/issuance-requests'),
      {
        'holder_pairwise_did': holderDid,
        'membership_class': membershipClass,
        'board_id': boardId,
        'proof_jwt': proof,
      },
    );
    final request = response['request'];
    if (request is! Map) {
      throw const Oid4vciWalletException(
        'invalid_response',
        'Issuer did not return an issuance request.',
      );
    }
    return _requiredString(Map<String, Object?>.from(request), 'id');
  }

  Future<WalletCredential> accept(Oid4vciCredentialOffer offer) async {
    final metadataUri = offer.credentialIssuer.replace(
      path:
          '/.well-known/openid-credential-issuer${offer.credentialIssuer.path}',
      query: null,
      fragment: null,
    );
    final metadata = await _getJson(metadataUri);
    if (metadata['credential_issuer'] != offer.credentialIssuer.toString()) {
      throw const Oid4vciWalletException(
        'issuer_mismatch',
        'Issuer metadata does not match the offer.',
      );
    }
    final configurations = metadata['credential_configurations_supported'];
    if (configurations is! Map ||
        !configurations.containsKey(offer.configurationId)) {
      throw const Oid4vciWalletException(
        'unsupported_credential',
        'Credential configuration is not supported.',
      );
    }

    final token = await _postForm(
      offer.credentialIssuer.resolve('${offer.credentialIssuer.path}/token'),
      {
        'grant_type': 'urn:ietf:params:oauth:grant-type:pre-authorized_code',
        'pre-authorized_code': offer.preAuthorizedCode,
      },
    );
    final accessToken = _requiredString(token, 'access_token');
    final nonceResponse = await _postJson(
      offer.credentialIssuer.resolve('${offer.credentialIssuer.path}/nonce'),
      const {},
    );
    final nonce = _requiredString(nonceResponse, 'c_nonce');
    final holderKey = _holderKey(offer.boardId);
    final proof = await _proofJwt(
      offer.credentialIssuer.toString(),
      nonce,
      holderKey,
    );

    final response = await _postJson(
      offer.credentialIssuer.resolve(
        '${offer.credentialIssuer.path}/credential',
      ),
      {
        'credential_configuration_id': offer.configurationId,
        'proofs': {
          'jwt': [proof],
        },
      },
      bearer: accessToken,
    );
    final credentials = response['credentials'];
    if (credentials is! List ||
        credentials.length != 1 ||
        credentials.first is! Map) {
      throw const Oid4vciWalletException(
        'invalid_credential_response',
        'Issuer did not return exactly one credential.',
      );
    }
    final compact = (credentials.first as Map)['credential'];
    if (compact is! String) {
      throw const Oid4vciWalletException(
        'invalid_credential_response',
        'Credential must be jwt_vc_json.',
      );
    }
    return _verifyAndStore(offer, compact, holderKey);
  }

  Future<String> _proofJwt(
    String audience,
    String nonce,
    HolderBindingKey holderKey,
  ) async {
    final key = await _hardwareHolderKey(holderKey);
    final jwk = _jwk(key);
    final header = _b64(
      jsonEncode({'alg': 'ES256', 'typ': 'openid4vci-proof+jwt', 'jwk': jwk}),
    );
    final claims = _b64(
      jsonEncode({
        'aud': audience,
        'iat': _now().millisecondsSinceEpoch ~/ 1000,
        'nonce': nonce,
      }),
    );
    final unsigned = '$header.$claims';
    final signature = await holderKey.sign(utf8.encode(unsigned));
    return '$unsigned.${_b64Bytes(ecdsaDerSignatureToJose(_hex(signature.hex)))}';
  }

  Future<IdentityPublicKey> _hardwareHolderKey(
    HolderBindingKey holderKey,
  ) async {
    final key = await holderKey.ensureKey();
    if (key.algorithm != IdentityKeyAlgorithm.p256Sha256 ||
        key.custody != IdentityKeyCustody.hardware) {
      throw const Oid4vciWalletException(
        'hardware_key_required',
        'Membership credentials require a hardware-backed holder key.',
      );
    }
    return key;
  }

  Map<String, String> _jwk(IdentityPublicKey key) {
    final bytes = _hex(key.publicKeyHex);
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': base64Url.encode(bytes.sublist(1, 33)).replaceAll('=', ''),
      'y': base64Url.encode(bytes.sublist(33, 65)).replaceAll('=', ''),
    };
  }

  Future<String> _pairwiseDid(HolderBindingKey holderKey) async {
    final jwk = _jwk(await _hardwareHolderKey(holderKey));
    return 'did:jwk:${_b64(jsonEncode({'crv': jwk['crv'], 'kty': jwk['kty'], 'x': jwk['x'], 'y': jwk['y']}))}';
  }

  Future<WalletCredential> _verifyAndStore(
    Oid4vciCredentialOffer offer,
    String compact,
    HolderBindingKey holderKey,
  ) async {
    final parts = compact.split('.');
    if (parts.length != 3) {
      throw const Oid4vciWalletException(
        'invalid_credential',
        'Credential JWT is malformed.',
      );
    }
    final header = _decodePart(parts[0]);
    final claims = _decodePart(parts[1]);
    if (header['alg'] != 'EdDSA') {
      throw const Oid4vciWalletException(
        'invalid_credential',
        'Unexpected credential signing algorithm.',
      );
    }
    final vcRaw = claims['vc'];
    if (vcRaw is! Map) {
      throw const Oid4vciWalletException(
        'invalid_credential',
        'Credential JWT has no VC payload.',
      );
    }
    final vc = Map<String, Object?>.from(vcRaw);
    final parsed = TrisAuraCredential.fromJson(vc);
    final holderDid = await _pairwiseDid(holderKey);
    final holderJwk = _jwk(await _hardwareHolderKey(holderKey));
    final confirmation = claims['cnf'];
    final confirmationJwk = confirmation is Map ? confirmation['jwk'] : null;
    if (parsed.holderDid != holderDid ||
        confirmationJwk is! Map ||
        confirmationJwk['kty'] != holderJwk['kty'] ||
        confirmationJwk['crv'] != holderJwk['crv'] ||
        confirmationJwk['x'] != holderJwk['x'] ||
        confirmationJwk['y'] != holderJwk['y']) {
      throw const Oid4vciWalletException(
        'holder_binding_mismatch',
        'Credential is not bound to this Wallet hardware key.',
      );
    }
    final subject = vc['credentialSubject'];
    if (subject is! Map || subject['board_id'] != offer.boardId) {
      throw const Oid4vciWalletException(
        'board_binding_mismatch',
        'Credential is not bound to the requested board.',
      );
    }
    final manifest = await _getJson(_manifestUri(offer.credentialIssuer));
    final tenant = manifest['tenant'];
    final signingKey = manifest['active_signing_key'];
    if (tenant is! Map ||
        tenant['organization_did'] != parsed.issuerDid ||
        signingKey is! Map ||
        signingKey['algorithm'] != 'EdDSA') {
      throw const Oid4vciWalletException(
        'untrusted_issuer',
        'Issuer manifest does not match the credential.',
      );
    }
    final multibase = signingKey['public_key_multibase'];
    if (multibase is! String || !multibase.startsWith('u')) {
      throw const Oid4vciWalletException(
        'invalid_issuer_key',
        'Issuer manifest key is invalid.',
      );
    }
    final publicKey = base64Url.decode(
      base64Url.normalize(multibase.substring(1)),
    );
    final valid = apiVerifySignature(
      publicKeyHex: _toHex(publicKey),
      messageHex: _toHex(utf8.encode('${parts[0]}.${parts[1]}')),
      signatureHex: _toHex(base64Url.decode(base64Url.normalize(parts[2]))),
    );
    if (!valid) {
      throw const Oid4vciWalletException(
        'invalid_credential_signature',
        'Credential signature is invalid.',
      );
    }
    final now = _now();
    if (!parsed.validUntil.isAfter(now) ||
        parsed.validFrom.isAfter(now.add(const Duration(seconds: 30)))) {
      throw const Oid4vciWalletException(
        'credential_expired',
        'Credential is outside its validity period.',
      );
    }
    await _verifyInitialStatus(
      credential: parsed,
      issuer: offer.credentialIssuer,
      issuerPublicKey: publicKey,
      issuerDid: parsed.issuerDid,
    );
    final wrapper = {
      'format': 'jwt_vc_json',
      'compact': compact,
      'board_id': offer.boardId,
      'vc': vc,
    };
    final sealed = await _payloadCodec.seal(
      credentialId: parsed.id,
      payloadJson: jsonEncode(wrapper),
    );
    final metadata = WalletCredential(
      credentialId: parsed.id,
      issuerDid: parsed.issuerDid,
      holderDid: parsed.holderDid,
      credentialType: parsed.types.last,
      status: WalletCredentialStatus.active,
      validFrom: parsed.validFrom,
      validUntil: parsed.validUntil,
      displayName: 'Membership credential',
      createdAt: now,
      updatedAt: now,
    );
    await _walletRepository.saveCredential(
      metadata: metadata,
      encryptedPayload: sealed.encodedPayload,
      encryptionVersion: sealed.encryptionVersion,
    );
    return metadata;
  }

  HolderBindingKey _holderKey(String boardId) =>
      _holderKeyOverride ?? BoardHolderKeyService(boardId: boardId);

  Uri _manifestUri(Uri issuer) {
    final segments = issuer.pathSegments;
    if (segments.length != 2 || segments.first != 'tenants') {
      throw const Oid4vciWalletException(
        'invalid_issuer',
        'Hosted issuer URL is not supported.',
      );
    }
    return issuer.replace(
      path: '/api/v1/hosted-issuers/${segments.last}/manifest',
    );
  }

  Future<void> _verifyInitialStatus({
    required TrisAuraCredential credential,
    required Uri issuer,
    required List<int> issuerPublicKey,
    required String issuerDid,
  }) async {
    if (credential.credentialStatus.length != 2) {
      throw const Oid4vciWalletException(
        'invalid_credential_status',
        'Membership credential must contain revocation and suspension status.',
      );
    }
    final seen = <String>{};
    for (final entry in credential.credentialStatus) {
      final purpose = entry['statusPurpose'];
      final index = int.tryParse(entry['statusListIndex']?.toString() ?? '');
      final url = Uri.tryParse(entry['statusListCredential'] as String? ?? '');
      if (purpose is! String ||
          (purpose != 'revocation' && purpose != 'suspension') ||
          !seen.add(purpose) ||
          index == null ||
          index < 0 ||
          url == null ||
          url.scheme != 'https' ||
          url.host != issuer.host ||
          !url.path.startsWith('${issuer.path}/status/$purpose/')) {
        throw const Oid4vciWalletException(
          'invalid_credential_status',
          'Credential status reference is invalid.',
        );
      }
      final compact = await _getRaw(url);
      final parts = compact.split('.');
      if (parts.length != 3) {
        throw const Oid4vciWalletException(
          'status_unavailable',
          'Credential status list is malformed.',
        );
      }
      final header = _decodePart(parts[0]);
      final claims = _decodePart(parts[1]);
      final statusVc = claims['vc'];
      final subject = statusVc is Map ? statusVc['credentialSubject'] : null;
      final issuedAt = claims['iat'];
      final encodedList = subject is Map ? subject['encodedList'] : null;
      final signed = utf8.encode('${parts[0]}.${parts[1]}');
      final signature = base64Url.decode(base64Url.normalize(parts[2]));
      if (header['alg'] != 'EdDSA' ||
          header['typ'] != 'JWT' ||
          claims['iss'] != issuerDid ||
          issuedAt is! int ||
          issuedAt > _now().millisecondsSinceEpoch ~/ 1000 + 30 ||
          issuedAt < _now().millisecondsSinceEpoch ~/ 1000 - 300 ||
          statusVc is! Map ||
          statusVc['id'] != url.toString() ||
          subject is! Map ||
          subject['statusPurpose'] != purpose ||
          encodedList is! String ||
          !encodedList.startsWith('u') ||
          !apiVerifySignature(
            publicKeyHex: _toHex(issuerPublicKey),
            messageHex: _toHex(signed),
            signatureHex: _toHex(signature),
          )) {
        throw const Oid4vciWalletException(
          'status_unavailable',
          'Credential status could not be verified.',
        );
      }
      List<int> bits;
      try {
        final compressed = base64Url.decode(
          base64Url.normalize(encodedList.substring(1)),
        );
        bits = GZipCodec().decode(compressed);
      } on Object {
        throw const Oid4vciWalletException(
          'status_unavailable',
          'Credential status list could not be decoded.',
        );
      }
      if (bits.length != 16384 || index >= bits.length * 8) {
        throw const Oid4vciWalletException(
          'status_unavailable',
          'Credential status index is invalid.',
        );
      }
      final set = bits[index ~/ 8] & (1 << (7 - index % 8)) != 0;
      if (set) {
        throw Oid4vciWalletException(
          purpose == 'revocation'
              ? 'credential_revoked'
              : 'credential_suspended',
          'Credential is not active.',
        );
      }
    }
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async =>
      _decode(await _http.get(uri).timeout(const Duration(seconds: 15)));
  Future<String> _getRaw(Uri uri) async {
    final response = await _http
        .get(uri, headers: const {'accept': 'application/vc+jwt'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.body.length > 1000000) {
      throw Oid4vciWalletException(
        'status_unavailable',
        'Credential status request failed.',
        statusCode: response.statusCode,
      );
    }
    return response.body.trim();
  }

  Future<Map<String, Object?>> _postForm(
    Uri uri,
    Map<String, String> body,
  ) async => _decode(
    await _http
        .post(
          uri,
          headers: const {'content-type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(const Duration(seconds: 15)),
  );
  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> body, {
    String? bearer,
  }) async => _decode(
    await _http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            if (bearer != null) 'authorization': 'Bearer $bearer',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15)),
  );

  Map<String, Object?> _decode(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map) {
      final code = decoded is Map
          ? decoded['error']?.toString()
          : 'invalid_response';
      throw Oid4vciWalletException(
        code ?? 'request_failed',
        'OID4VCI request failed.',
        statusCode: response.statusCode,
      );
    }
    return Map<String, Object?>.from(decoded);
  }
}

class HardwareHolderJwtSigner {
  HardwareHolderJwtSigner({HolderBindingKey? key})
    : _key = key ?? WalletHolderKeyService();

  final HolderBindingKey _key;

  Future<Map<String, String>> jwk() async {
    final publicKey = await _key.ensureKey();
    if (publicKey.algorithm != IdentityKeyAlgorithm.p256Sha256 ||
        publicKey.custody != IdentityKeyCustody.hardware) {
      throw StateError('A hardware-backed P-256 holder key is required.');
    }
    final bytes = _hex(publicKey.publicKeyHex);
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _b64Bytes(bytes.sublist(1, 33)),
      'y': _b64Bytes(bytes.sublist(33, 65)),
    };
  }

  Future<String> pairwiseDid() async =>
      'did:jwk:${_b64(_canonicalJwk(await jwk()))}';

  Future<String> encodedJwk() async => _b64(_canonicalJwk(await jwk()));

  Future<String> thumbprint() async =>
      _b64Bytes(sha256.convert(utf8.encode(_canonicalJwk(await jwk()))).bytes);

  Future<String> signJwt({
    required String typ,
    required Map<String, Object?> claims,
  }) async {
    final header = _b64(
      jsonEncode({'alg': 'ES256', 'typ': typ, 'jwk': await jwk()}),
    );
    final payload = _b64(jsonEncode(claims));
    final unsigned = '$header.$payload';
    final signature = await _key.sign(utf8.encode(unsigned));
    return '$unsigned.${_b64Bytes(ecdsaDerSignatureToJose(_hex(signature.hex)))}';
  }

  Future<String> signRequest(String canonicalRequest) async =>
      (await _key.sign(utf8.encode(canonicalRequest))).hex;

  String _canonicalJwk(Map<String, String> value) => jsonEncode({
    'crv': value['crv'],
    'kty': value['kty'],
    'x': value['x'],
    'y': value['y'],
  });
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) return value;
  throw Oid4vciWalletException('invalid_response', 'Missing $key.');
}

Map<String, Object?> _decodePart(String part) {
  final value = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(part))),
  );
  if (value is Map) return Map<String, Object?>.from(value);
  throw const Oid4vciWalletException(
    'invalid_credential',
    'JWT part must be an object.',
  );
}

String _b64(String value) => _b64Bytes(utf8.encode(value));
String _b64Bytes(List<int> value) =>
    base64Url.encode(value).replaceAll('=', '');
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
String _toHex(List<int> value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<int> ecdsaDerSignatureToJose(List<int> der) {
  if (der.length < 8 || der[0] != 0x30) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  var offset = 1;
  final sequenceLength = _derLength(der, offset);
  offset = sequenceLength.$2;
  if (offset + sequenceLength.$1 != der.length || der[offset++] != 0x02) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  final rLength = _derLength(der, offset);
  offset = rLength.$2;
  final r = der.sublist(offset, offset + rLength.$1);
  offset += rLength.$1;
  if (der[offset++] != 0x02) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  final sLength = _derLength(der, offset);
  offset = sLength.$2;
  final s = der.sublist(offset, offset + sLength.$1);
  return [..._unsigned32(r), ..._unsigned32(s)];
}

(int, int) _derLength(List<int> bytes, int offset) {
  final first = bytes[offset++];
  if (first < 0x80) return (first, offset);
  final count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count > bytes.length) {
    throw const FormatException('Invalid DER length.');
  }
  var length = 0;
  for (var i = 0; i < count; i++) {
    length = (length << 8) | bytes[offset++];
  }
  return (length, offset);
}

List<int> _unsigned32(List<int> integer) {
  var value = integer;
  while (value.length > 32 && value.first == 0) {
    value = value.sublist(1);
  }
  if (value.length > 32) {
    throw const FormatException('ECDSA integer is too large.');
  }
  return [...List<int>.filled(32 - value.length, 0), ...value];
}
