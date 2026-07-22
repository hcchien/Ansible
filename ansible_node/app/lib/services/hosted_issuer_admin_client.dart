import 'dart:convert';
import 'dart:math';

import 'package:ansible_did/ansible_did.dart';
import 'package:http/http.dart' as http;

import '../config/protocol.dart';
import 'sync_capability_service.dart';

class HostedIssuerAdminException implements Exception {
  const HostedIssuerAdminException(this.statusCode, this.code);

  final int statusCode;
  final String code;

  @override
  String toString() => 'HostedIssuerAdminException($statusCode $code)';
}

abstract class IssuerRootSigningKey {
  Future<IdentityPublicKey> ensureHardwareKey();
  Future<IdentitySignature> sign(List<int> message);
}

class HardwareIssuerRootSigningKey implements IssuerRootSigningKey {
  HardwareIssuerRootSigningKey({HardwarePurposeKey? key})
    : _key =
          key ??
          HardwarePurposeKey(HardwareKeyPurpose.issuerRootAdministration);

  final HardwarePurposeKey _key;

  @override
  Future<IdentityPublicKey> ensureHardwareKey() async {
    final publicKey = await _key.load() ?? await _key.generate();
    if (publicKey.algorithm != IdentityKeyAlgorithm.p256Sha256 ||
        publicKey.custody != IdentityKeyCustody.hardware) {
      throw StateError(
        'Hosted Issuer administration requires a hardware-backed P-256 key.',
      );
    }
    return publicKey;
  }

  @override
  Future<IdentitySignature> sign(List<int> message) => _key.sign(message);
}

class HostedIssuerTenant {
  const HostedIssuerTenant({
    required this.id,
    required this.organizationDid,
    required this.serviceSlug,
    required this.status,
    required this.approvalThreshold,
  });

  final String id;
  final String organizationDid;
  final String serviceSlug;
  final String status;
  final int approvalThreshold;

  factory HostedIssuerTenant.fromJson(Map<String, dynamic> json) {
    return HostedIssuerTenant(
      id: json['id'] as String,
      organizationDid: json['organization_did'] as String,
      serviceSlug: json['service_slug'] as String,
      status: json['status'] as String,
      approvalThreshold: (json['approval_threshold'] as num).toInt(),
    );
  }
}

class HostedIssuerAdminCapability {
  const HostedIssuerAdminCapability({
    required this.token,
    required this.expiresAt,
    required this.scopes,
    required this.audience,
  });

  final String token;
  final DateTime expiresAt;
  final Set<String> scopes;
  final String audience;
}

class HostedIssuanceRequest {
  const HostedIssuanceRequest({
    required this.id,
    required this.applicantHash,
    required this.payloadHash,
    required this.membershipClass,
    required this.state,
    required this.approvalCount,
    required this.approvalThreshold,
    required this.expiresAt,
  });

  final String id;
  final String applicantHash;
  final String payloadHash;
  final String membershipClass;
  final String state;
  final int approvalCount;
  final int approvalThreshold;
  final DateTime expiresAt;

  factory HostedIssuanceRequest.fromJson(Map<String, dynamic> json) {
    final snapshot = json['policy_snapshot'];
    if (snapshot is! Map) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    final expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
    if (expiresAt == null) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    return HostedIssuanceRequest(
      id: _requiredString(json, 'id'),
      applicantHash: _requiredString(json, 'applicant_hash'),
      payloadHash: _requiredString(json, 'payload_hash'),
      membershipClass: _requiredString(json, 'membership_class'),
      state: _requiredString(json, 'state'),
      approvalCount: (json['approval_count'] as num? ?? 0).toInt(),
      approvalThreshold: (snapshot['approval_threshold'] as num? ?? 0).toInt(),
      expiresAt: expiresAt.toUtc(),
    );
  }
}

class HostedIssuerAdminClient {
  HostedIssuerAdminClient({
    required String baseUrl,
    required String ownerDid,
    IssuerRootSigningKey? rootKey,
    WebAuthnPlatform? webAuthn,
    http.Client? client,
    DateTime Function()? now,
    Random? random,
  }) : _baseUri = Uri.parse(baseUrl),
       _ownerDid = ownerDid,
       _rootKey = rootKey ?? HardwareIssuerRootSigningKey(),
       _webAuthn = webAuthn ?? NativeWebAuthnPlatform(),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final Uri _baseUri;
  final String _ownerDid;
  final IssuerRootSigningKey _rootKey;
  final WebAuthnPlatform _webAuthn;
  final http.Client _client;
  final DateTime Function() _now;
  final Random _random;

  Future<HostedIssuerTenant> bootstrap({
    required String organizationDid,
    required String serviceSlug,
    required int approvalThreshold,
    required int administratorCount,
  }) async {
    final key = await _rootKey.ensureHardwareKey();
    final issuedAt = _rfc3339Seconds(_now().toUtc());
    final unsigned = <String, Object?>{
      'type': 'HostedIssuerBootstrap',
      'version': 1,
      'organization_did': organizationDid,
      'service_slug': serviceSlug,
      'approval_threshold': approvalThreshold,
      'administrator_count': administratorCount,
      'owner_did': _ownerDid,
      'owner_public_key_hex': key.publicKeyHex,
      'owner_key_algorithm': key.algorithm.wireName,
      'owner_custody': key.custody.wireName,
      'issued_at': issuedAt,
    };
    final signature = await _rootKey.sign(utf8.encode(jsonEncode(unsigned)));
    final response = await _post('/api/v1/hosted-issuers', {
      ...unsigned,
      'signature_hex': signature.hex,
    });
    final tenant = response['tenant'];
    if (tenant is! Map<String, dynamic>) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    return HostedIssuerTenant.fromJson(tenant);
  }

  Future<void> enrollAdministratorPasskey(String tenantId) async {
    final issuedAt = _rfc3339Seconds(_now().toUtc());
    final nonce = List<int>.generate(24, (_) => _random.nextInt(256));
    final unsigned = <String, Object?>{
      'type': 'IssuerAdminWebAuthnEnrollment',
      'version': 1,
      'tenant_id': tenantId,
      'admin_did': _ownerDid,
      'client_nonce': base64Url.encode(nonce).replaceAll('=', ''),
      'issued_at': issuedAt,
    };
    final signature = await _rootKey.sign(utf8.encode(jsonEncode(unsigned)));
    final options = await _post(
      '/api/v1/hosted-issuers/$tenantId/admin/webauthn/register/options',
      {...unsigned, 'signature_hex': signature.hex},
    );
    final ceremonyId = options['ceremony_id'];
    final publicKey = options['publicKey'];
    if (ceremonyId is! String || publicKey is! Map<String, dynamic>) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    final credential = await _webAuthn.register(publicKey);
    final path =
        '/api/v1/hosted-issuers/$tenantId/admin/webauthn/register/verify';
    await _post(
      path,
      credential,
      query: {'admin_did': _ownerDid, 'ceremony_id': ceremonyId},
    );
  }

  Future<HostedIssuerAdminCapability> authenticateAdministrator({
    required String tenantId,
    required Set<String> scopes,
  }) async {
    final options = await _post(
      '/api/v1/hosted-issuers/$tenantId/admin/webauthn/authenticate/options',
      {'admin_did': _ownerDid, 'scopes': scopes.toList()..sort()},
    );
    final ceremonyId = options['ceremony_id'];
    final publicKey = options['publicKey'];
    if (ceremonyId is! String || publicKey is! Map<String, dynamic>) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    final assertion = await _webAuthn.authenticate(publicKey);
    final response = await _post(
      '/api/v1/hosted-issuers/$tenantId/admin/webauthn/authenticate/verify',
      assertion,
      query: {'admin_did': _ownerDid, 'ceremony_id': ceremonyId},
    );
    final token = response['access_token'];
    final expiresAt = DateTime.tryParse(
      response['expires_at'] as String? ?? '',
    );
    final audience = response['audience'];
    if (token is! String || expiresAt == null || audience is! String) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    final returnedScopes = (response['scope'] as String? ?? '')
        .split(' ')
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!returnedScopes.containsAll(scopes)) {
      throw const HostedIssuerAdminException(403, 'scope_not_granted');
    }
    return HostedIssuerAdminCapability(
      token: token,
      expiresAt: expiresAt.toUtc(),
      scopes: returnedScopes,
      audience: audience,
    );
  }

  Future<Map<String, Object?>> createAdministratorEnrollment({
    required String tenantId,
  }) async {
    final key = await _rootKey.ensureHardwareKey();
    final unsigned = <String, Object?>{
      'type': 'IssuerAdministratorEnrollment',
      'version': 1,
      'tenant_id': tenantId,
      'administrator_did': _ownerDid,
      'role': 'administrator',
      'signing_algorithm': key.algorithm.wireName,
      'public_key_hex': key.publicKeyHex,
      'custody': key.custody.wireName,
      'issued_at': _rfc3339Seconds(_now().toUtc()),
    };
    final signature = await _rootKey.sign(utf8.encode(jsonEncode(unsigned)));
    return {...unsigned, 'applicant_signature_hex': signature.hex};
  }

  Future<void> addAdministrator({
    required String tenantId,
    required Map<String, Object?> applicantEnrollment,
    required HostedIssuerAdminCapability capability,
  }) async {
    final unsigned = _administratorEnrollmentUnsigned(applicantEnrollment);
    if (unsigned['tenant_id'] != tenantId ||
        applicantEnrollment['applicant_signature_hex'] is! String) {
      throw const HostedIssuerAdminException(
        422,
        'administrator_enrollment_invalid',
      );
    }
    final inviterSignature = await _rootKey.sign(
      utf8.encode(jsonEncode(unsigned)),
    );
    await _authorizedPost('/api/v1/hosted-issuers/$tenantId/administrators', {
      ...unsigned,
      'applicant_signature_hex': applicantEnrollment['applicant_signature_hex'],
      'inviter_signature_hex': inviterSignature.hex,
    }, capability);
  }

  Future<Map<String, dynamic>> registerOperationalKey({
    required String tenantId,
    required String kmsKeyVersion,
    required int version,
    required HostedIssuerAdminCapability capability,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/hosted-issuers/$tenantId/keys',
      {'kms_key_version': kmsKeyVersion, 'version': version},
      capability,
    );
    return _requiredMap(response, 'key');
  }

  Future<Map<String, dynamic>> putMembershipTemplate({
    required String tenantId,
    required int version,
    required int maxTtlDays,
    required bool active,
    required HostedIssuerAdminCapability capability,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/hosted-issuers/$tenantId/credential-templates/membership',
      {'version': version, 'max_ttl_days': maxTtlDays, 'active': active},
      capability,
    );
    return _requiredMap(response, 'template');
  }

  Future<String> decideIssuanceRequest({
    required String tenantId,
    required String requestId,
    required String decision,
    required HostedIssuerAdminCapability capability,
  }) async {
    if (decision != 'approve' && decision != 'deny') {
      throw ArgumentError.value(decision, 'decision');
    }
    final unsigned = <String, Object?>{
      'type': 'CredentialIssuanceDecision',
      'version': 1,
      'tenant_id': tenantId,
      'request_id': requestId,
      'decision': decision,
      'issued_at': _rfc3339Seconds(_now().toUtc()),
    };
    final signature = await _rootKey.sign(utf8.encode(jsonEncode(unsigned)));
    final response = await _authorizedPost(
      '/api/v1/hosted-issuers/$tenantId/issuance-requests/$requestId/decisions',
      {...unsigned, 'signature_hex': signature.hex},
      capability,
    );
    return _requiredString(_requiredMap(response, 'request'), 'state');
  }

  Future<List<HostedIssuanceRequest>> listIssuanceRequests({
    required String tenantId,
    String state = 'pending',
    required HostedIssuerAdminCapability capability,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/hosted-issuers/$tenantId/issuance-requests',
      capability,
      query: {'state': state},
    );
    final requests = response['requests'];
    if (requests is! List) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    return requests
        .whereType<Map>()
        .map(
          (request) => HostedIssuanceRequest.fromJson(
            Map<String, dynamic>.from(request),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createCredentialOffer({
    required String tenantId,
    required String requestId,
    required HostedIssuerAdminCapability capability,
  }) => _authorizedPost('/api/v1/hosted-issuers/$tenantId/credential-offers', {
    'request_id': requestId,
  }, capability);

  Future<void> setCredentialStatus({
    required String tenantId,
    required String credentialId,
    required String status,
    required HostedIssuerAdminCapability capability,
  }) async {
    if (status != 'active' && status != 'suspended' && status != 'revoked') {
      throw ArgumentError.value(status, 'status');
    }
    final unsigned = <String, Object?>{
      'type': 'CredentialStatusDecision',
      'version': 1,
      'tenant_id': tenantId,
      'credential_id': credentialId,
      'status': status,
      'issued_at': _rfc3339Seconds(_now().toUtc()),
    };
    final signature = await _rootKey.sign(utf8.encode(jsonEncode(unsigned)));
    await _authorizedPost(
      '/api/v1/hosted-issuers/$tenantId/credentials/$credentialId/status',
      {...unsigned, 'signature_hex': signature.hex},
      capability,
    );
  }

  Future<String> proposeDelegation({
    required String tenantId,
    required String signingKeyId,
    required Map<String, Object?> canonicalPayload,
    required HostedIssuerAdminCapability capability,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/hosted-issuers/$tenantId/delegations',
      {
        'id': '',
        'signing_key_id': signingKeyId,
        'canonical_payload': canonicalPayload,
      },
      capability,
    );
    final id = response['id'];
    if (id is! String || id.isEmpty) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    return id;
  }

  Future<void> approveDelegation({
    required String tenantId,
    required String delegationId,
    required Map<String, Object?> canonicalPayload,
    required HostedIssuerAdminCapability capability,
  }) async {
    final signature = await _rootKey.sign(
      utf8.encode(jsonEncode(canonicalPayload)),
    );
    await _authorizedPost(
      '/api/v1/hosted-issuers/$tenantId/delegations/$delegationId/approve',
      {'canonical_payload': canonicalPayload, 'signature_hex': signature.hex},
      capability,
    );
  }

  Future<void> activateDelegation({
    required String tenantId,
    required String delegationId,
    required HostedIssuerAdminCapability capability,
  }) => _authorizedPost(
    '/api/v1/hosted-issuers/$tenantId/delegations/$delegationId/activate',
    const {},
    capability,
  ).then((_) {});

  Future<void> revokeDelegation({
    required String tenantId,
    required String delegationId,
    required HostedIssuerAdminCapability capability,
  }) => _authorizedPost(
    '/api/v1/hosted-issuers/$tenantId/delegations/$delegationId/revoke',
    const {},
    capability,
  ).then((_) {});

  Future<List<Map<String, dynamic>>> exportAudit({
    required String tenantId,
    required HostedIssuerAdminCapability capability,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/hosted-issuers/$tenantId/audit/export',
      capability,
    );
    final events = response['events'];
    if (events is! List) {
      throw const HostedIssuerAdminException(502, 'invalid_response');
    }
    return events
        .whereType<Map>()
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
  }

  static Map<String, Object?> delegationPayload({
    required String issuerDid,
    required String delegateKey,
    required String service,
    required List<String> credentialTypes,
    required DateTime notBefore,
    required DateTime expiresAt,
    required int threshold,
    required int administratorCount,
    required int sequence,
  }) => <String, Object?>{
    'type': 'IssuerKeyDelegation',
    'version': 1,
    'issuer': issuerDid,
    'delegate_key': delegateKey,
    'service': service,
    'credential_types': credentialTypes,
    'not_before': _rfc3339Seconds(notBefore),
    'expires_at': _rfc3339Seconds(expiresAt),
    'approval_policy': {
      'threshold': threshold,
      'administrators': administratorCount,
    },
    'sequence': sequence,
  };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    Map<String, String>? query,
  }) async {
    final response = await _client.post(
      _endpoint(path, query),
      headers: const {
        'content-type': 'application/json',
        ...AnsibleProtocol.headers,
      },
      body: jsonEncode(body),
    );
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final object = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HostedIssuerAdminException(
        response.statusCode,
        object['error'] as String? ?? 'issuer_admin_request_failed',
      );
    }
    return object;
  }

  Future<Map<String, dynamic>> _authorizedPost(
    String path,
    Map<String, Object?> body,
    HostedIssuerAdminCapability capability,
  ) async {
    final response = await _client.post(
      _endpoint(path, null),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${capability.token}',
        ...AnsibleProtocol.headers,
      },
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _authorizedGet(
    String path,
    HostedIssuerAdminCapability capability, {
    Map<String, String>? query,
  }) async {
    final response = await _client.get(
      _endpoint(path, query),
      headers: {
        'authorization': 'Bearer ${capability.token}',
        ...AnsibleProtocol.headers,
      },
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final object = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HostedIssuerAdminException(
        response.statusCode,
        object['error'] as String? ?? 'issuer_admin_request_failed',
      );
    }
    return object;
  }

  Uri _endpoint(String path, Map<String, String>? query) {
    final prefix = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$prefix$path', queryParameters: query);
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is Map<String, dynamic>) return value;
  throw const HostedIssuerAdminException(502, 'invalid_response');
}

String _requiredString(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is String && value.isNotEmpty) return value;
  throw const HostedIssuerAdminException(502, 'invalid_response');
}

Map<String, Object?> _administratorEnrollmentUnsigned(
  Map<String, Object?> enrollment,
) => <String, Object?>{
  'type': enrollment['type'],
  'version': enrollment['version'],
  'tenant_id': enrollment['tenant_id'],
  'administrator_did': enrollment['administrator_did'],
  'role': enrollment['role'],
  'signing_algorithm': enrollment['signing_algorithm'],
  'public_key_hex': enrollment['public_key_hex'],
  'custody': enrollment['custody'],
  'issued_at': enrollment['issued_at'],
};

String _rfc3339Seconds(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d{3}Z$'), 'Z');
