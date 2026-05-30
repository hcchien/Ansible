import 'dart:convert';

class Oid4vpRequestException implements Exception {
  const Oid4vpRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'Oid4vpRequestException($code): $message';
}

class Oid4vpAuthorizationRequest {
  const Oid4vpAuthorizationRequest({
    required this.clientId,
    required this.audience,
    required this.responseUri,
    required this.nonce,
    required this.presentationDefinition,
    required this.presentationDefinitionId,
    required this.inputDescriptorId,
    required this.requiredCredentialType,
    required this.requestedClaimLabels,
    this.state,
  });

  static const supportedCredentialType = 'TrisAuraHumanityCredential';

  final String clientId;
  final String audience;
  final Uri responseUri;
  final String nonce;
  final String? state;
  final Map<String, Object?> presentationDefinition;
  final String presentationDefinitionId;
  final String inputDescriptorId;
  final String requiredCredentialType;
  final List<String> requestedClaimLabels;

  String get verifierLabel {
    final parsed = Uri.tryParse(clientId);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.origin;
    }
    return clientId;
  }

  Map<String, Object?> presentationSubmission() {
    return {
      'id': 'submission-$presentationDefinitionId',
      'definition_id': presentationDefinitionId,
      'descriptor_map': [
        {
          'id': inputDescriptorId,
          'format': 'ldp_vp',
          'path': r'$.vp_token',
          'path_nested': {
            'format': 'ldp_vc',
            'path': r'$.verifiableCredential[0]',
          },
        },
      ],
    };
  }

  static Oid4vpAuthorizationRequest parse(
    String raw, {
    bool allowLocalHttp = false,
  }) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) {
      throw const Oid4vpRequestException(
        'invalid_request_uri',
        'Verifier request QR is not a valid URI.',
      );
    }
    _validateRequestScheme(uri, allowLocalHttp: allowLocalHttp);

    final params = uri.queryParameters;
    if (params.containsKey('request_uri')) {
      throw const Oid4vpRequestException(
        'request_uri_not_supported',
        'request_uri verifier requests are not supported in this wallet MVP.',
      );
    }

    final responseType = _requiredParam(params, 'response_type');
    if (responseType != 'vp_token') {
      throw const Oid4vpRequestException(
        'unsupported_response_type',
        'Only vp_token verifier requests are supported.',
      );
    }
    final responseMode = _requiredParam(params, 'response_mode');
    if (responseMode != 'direct_post') {
      throw const Oid4vpRequestException(
        'unsupported_response_mode',
        'Only direct_post verifier requests are supported.',
      );
    }

    final clientId = _requiredParam(params, 'client_id');
    final nonce = _requiredParam(params, 'nonce');
    final responseUri = Uri.tryParse(_requiredParam(params, 'response_uri'));
    if (responseUri == null ||
        !responseUri.hasScheme ||
        !responseUri.hasAuthority) {
      throw const Oid4vpRequestException(
        'invalid_response_uri',
        'Verifier response_uri must be an absolute URI.',
      );
    }
    _validateResponseUri(responseUri, allowLocalHttp: allowLocalHttp);

    final definitionRaw = _requiredParam(params, 'presentation_definition');
    final definition = _decodePresentationDefinition(definitionRaw);
    final definitionId = _requiredString(definition, 'id');
    final descriptors = definition['input_descriptors'];
    if (descriptors is! List || descriptors.isEmpty) {
      throw const Oid4vpRequestException(
        'invalid_presentation_definition',
        'presentation_definition must contain at least one input descriptor.',
      );
    }
    final firstDescriptorRaw = descriptors.first;
    if (firstDescriptorRaw is! Map) {
      throw const Oid4vpRequestException(
        'invalid_presentation_definition',
        'input descriptor must be an object.',
      );
    }
    final firstDescriptor = Map<String, Object?>.from(firstDescriptorRaw);
    final descriptorId = _requiredString(firstDescriptor, 'id');

    final credentialType = _extractCredentialType(definition);
    if (credentialType != supportedCredentialType) {
      throw const Oid4vpRequestException(
        'unsupported_credential_type',
        'Only TrisAuraHumanityCredential verifier requests are supported.',
      );
    }

    return Oid4vpAuthorizationRequest(
      clientId: clientId,
      audience: clientId,
      responseUri: responseUri,
      nonce: nonce,
      state: params['state'],
      presentationDefinition: Map<String, Object?>.unmodifiable(definition),
      presentationDefinitionId: definitionId,
      inputDescriptorId: descriptorId,
      requiredCredentialType: credentialType,
      requestedClaimLabels: List<String>.unmodifiable(
        _extractRequestedClaimLabels(definition),
      ),
    );
  }

  static String _requiredParam(Map<String, String> params, String key) {
    final value = params[key];
    if (value != null && value.trim().isNotEmpty) return value.trim();
    throw Oid4vpRequestException(
      'missing_$key',
      'Verifier request is missing $key.',
    );
  }

  static Map<String, Object?> _decodePresentationDefinition(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      throw const Oid4vpRequestException(
        'invalid_presentation_definition',
        'presentation_definition must be JSON.',
      );
    }
    throw const Oid4vpRequestException(
      'invalid_presentation_definition',
      'presentation_definition must be a JSON object.',
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw Oid4vpRequestException(
      'invalid_presentation_definition',
      'presentation_definition field $key must be a non-empty string.',
    );
  }

  static String _extractCredentialType(Object? value) {
    if (_containsString(value, supportedCredentialType)) {
      return supportedCredentialType;
    }
    return '';
  }

  static bool _containsString(Object? value, String needle) {
    if (value is String) return value == needle;
    if (value is Iterable) {
      return value.any((item) => _containsString(item, needle));
    }
    if (value is Map) {
      return value.values.any((item) => _containsString(item, needle));
    }
    return false;
  }

  static List<String> _extractRequestedClaimLabels(Object? definition) {
    final labels = <String>{};
    _collectClaimLabels(definition, labels);
    labels.remove('type');
    if (labels.isEmpty) {
      labels.add('humanVerified');
    }
    return labels.toList()..sort();
  }

  static void _collectClaimLabels(Object? value, Set<String> labels) {
    if (value is Map) {
      final path = value['path'];
      if (path is List) {
        for (final item in path) {
          if (item is String) {
            final label = _claimLabelFromPath(item);
            if (label != null) labels.add(label);
          }
        }
      } else if (path is String) {
        final label = _claimLabelFromPath(path);
        if (label != null) labels.add(label);
      }
      for (final nested in value.values) {
        _collectClaimLabels(nested, labels);
      }
      return;
    }
    if (value is Iterable) {
      for (final nested in value) {
        _collectClaimLabels(nested, labels);
      }
    }
  }

  static String? _claimLabelFromPath(String path) {
    const prefix = r'$.credentialSubject.';
    if (path.startsWith(prefix)) {
      final tail = path.substring(prefix.length);
      if (tail.isNotEmpty && !tail.contains('[')) {
        return tail;
      }
    }
    if (path == r'$.type') return 'type';
    return null;
  }

  static void _validateRequestScheme(Uri uri, {required bool allowLocalHttp}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'openid4vp' || scheme == 'https') return;
    if (scheme == 'http' && allowLocalHttp && _isLocalHost(uri.host)) {
      return;
    }
    throw const Oid4vpRequestException(
      'unsupported_request_scheme',
      'Verifier request QR must use openid4vp or https.',
    );
  }

  static void _validateResponseUri(Uri uri, {required bool allowLocalHttp}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return;
    if (scheme == 'http' && allowLocalHttp && _isLocalHost(uri.host)) {
      return;
    }
    throw const Oid4vpRequestException(
      'insecure_response_uri',
      'Verifier response_uri must use https.',
    );
  }

  static bool _isLocalHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }
}
