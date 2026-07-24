import 'dart:convert';

import 'package:http/http.dart' as http;

class HostedIssuerManifestException implements Exception {
  const HostedIssuerManifestException(this.code);

  final String code;
}

class HostedIssuerClaimConfiguration {
  const HostedIssuerClaimConfiguration({
    required this.path,
    required this.allowedOperators,
  });

  final String path;
  final Set<String> allowedOperators;
}

class HostedIssuerCredentialConfiguration {
  const HostedIssuerCredentialConfiguration({
    required this.id,
    required this.credentialType,
    required this.claims,
  });

  final String id;
  final String credentialType;
  final List<HostedIssuerClaimConfiguration> claims;
}

class HostedIssuerManifest {
  const HostedIssuerManifest({
    required this.organizationDid,
    required this.configurations,
  });

  final String organizationDid;
  final List<HostedIssuerCredentialConfiguration> configurations;
}

abstract class HostedIssuerManifestLoader {
  Future<HostedIssuerManifest> load(Uri manifestUri);
}

class HostedIssuerManifestClient implements HostedIssuerManifestLoader {
  HostedIssuerManifestClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  static const _prohibitedClaims = {
    'nationalId',
    'legalName',
    'birthDate',
    'documentNumber',
    'passportNumber',
    'nationalIdHash',
    'passportNumberHash',
    'rawProviderAssertion',
  };

  @override
  Future<HostedIssuerManifest> load(Uri manifestUri) async {
    if (manifestUri.scheme != 'https' || manifestUri.host.isEmpty) {
      throw const HostedIssuerManifestException('insecure_manifest_uri');
    }
    final response = await _client.get(manifestUri).timeout(timeout);
    if (response.statusCode != 200) {
      throw const HostedIssuerManifestException('manifest_unavailable');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const HostedIssuerManifestException('invalid_manifest');
    }
    final tenant = decoded['tenant'];
    final rawConfigurations = decoded['credential_configurations'];
    if (tenant is! Map || rawConfigurations is! List) {
      throw const HostedIssuerManifestException('invalid_manifest');
    }
    final organizationDid = tenant['organization_did'];
    if (organizationDid is! String ||
        !organizationDid.startsWith('did:') ||
        organizationDid.length > 256) {
      throw const HostedIssuerManifestException('invalid_manifest');
    }
    final configurations = rawConfigurations
        .map(_configurationFromJson)
        .toList(growable: false);
    return HostedIssuerManifest(
      organizationDid: organizationDid,
      configurations: configurations,
    );
  }

  HostedIssuerCredentialConfiguration _configurationFromJson(Object? raw) {
    if (raw is! Map) {
      throw const HostedIssuerManifestException('invalid_manifest');
    }
    final id = raw['id'];
    final type = raw['credential_type'];
    final rawClaims = raw['claims'];
    if (id is! String ||
        id.isEmpty ||
        type is! String ||
        !type.endsWith('Credential') ||
        rawClaims is! List) {
      throw const HostedIssuerManifestException('invalid_manifest');
    }
    final claims = rawClaims
        .map((rawClaim) {
          if (rawClaim is! Map ||
              rawClaim['disclosable'] != true ||
              rawClaim['path'] is! String ||
              !_safeClaimPath(rawClaim['path'] as String) ||
              rawClaim['allowed_operators'] is! List ||
              !(rawClaim['allowed_operators'] as List).contains('equals')) {
            throw const HostedIssuerManifestException('invalid_manifest');
          }
          return HostedIssuerClaimConfiguration(
            path: rawClaim['path'] as String,
            allowedOperators: (rawClaim['allowed_operators'] as List)
                .whereType<String>()
                .toSet(),
          );
        })
        .toList(growable: false);
    return HostedIssuerCredentialConfiguration(
      id: id,
      credentialType: type,
      claims: claims,
    );
  }

  bool _safeClaimPath(String path) {
    final segments = path.split('.');
    return segments.isNotEmpty &&
        segments.length <= 4 &&
        segments.every(
          (segment) =>
              RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(segment) &&
              !_prohibitedClaims.contains(segment),
        );
  }
}
