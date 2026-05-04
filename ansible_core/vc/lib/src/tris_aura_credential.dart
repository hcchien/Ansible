class TrisAuraCredentialException implements Exception {
  final String code;
  final String message;

  TrisAuraCredentialException(this.code, this.message);

  @override
  String toString() => 'TrisAuraCredentialException($code): $message';
}

class TrisAuraCredential {
  static const prohibitedClaims = {
    'nationalId',
    'legalName',
    'birthDate',
    'householdRegistrationAddress',
    'certificateSerialNumber',
    'phone',
    'email',
    'rawProviderAssertion',
  };

  final Map<String, Object?> json;
  final String id;
  final List<String> types;
  final String issuerDid;
  final String holderDid;
  final DateTime validFrom;
  final DateTime validUntil;
  final Map<String, Object?> claims;
  final Map<String, Object?>? credentialStatus;
  final Map<String, Object?>? proof;

  TrisAuraCredential._({
    required this.json,
    required this.id,
    required this.types,
    required this.issuerDid,
    required this.holderDid,
    required this.validFrom,
    required this.validUntil,
    required this.claims,
    required this.credentialStatus,
    required this.proof,
  });

  factory TrisAuraCredential.fromJson(Map<String, Object?> json) {
    final subject = _requiredMap(json, 'credentialSubject');
    final prohibitedClaim = _findProhibitedClaim(subject);
    if (prohibitedClaim != null) {
      throw TrisAuraCredentialException(
        'prohibited_claim',
        'Credential contains prohibited claim "$prohibitedClaim".',
      );
    }

    final types = _requiredStringList(json, 'type');

    return TrisAuraCredential._(
      json: _deepCopy(json),
      id: _requiredString(json, 'id'),
      types: types,
      issuerDid: _requiredString(json, 'issuer'),
      holderDid: _requiredString(subject, 'id'),
      validFrom: DateTime.parse(_requiredString(json, 'validFrom')).toUtc(),
      validUntil: DateTime.parse(_requiredString(json, 'validUntil')).toUtc(),
      claims: Map<String, Object?>.unmodifiable(subject),
      credentialStatus: _optionalMap(json, 'credentialStatus'),
      proof: _optionalMap(json, 'proof'),
    );
  }

  bool hasType(String type) => types.contains(type);

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw TrisAuraCredentialException(
      'invalid_credential',
      'Credential field "$key" must be a non-empty string.',
    );
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    throw TrisAuraCredentialException(
      'invalid_credential',
      'Credential field "$key" must be an object.',
    );
  }

  static Map<String, Object?>? _optionalMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    throw TrisAuraCredentialException(
      'invalid_credential',
      'Credential field "$key" must be an object.',
    );
  }

  static List<String> _requiredStringList(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is List && value.every((item) => item is String)) {
      return List<String>.unmodifiable(value.cast<String>());
    }
    throw TrisAuraCredentialException(
      'invalid_credential',
      'Credential field "$key" must be a string list.',
    );
  }

  static Map<String, Object?> _deepCopy(Map<String, Object?> source) {
    return Map<String, Object?>.unmodifiable(
      source.map((key, value) => MapEntry(key, _copyValue(value))),
    );
  }

  static Object? _copyValue(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(
        value.map(
          (key, nested) => MapEntry(key.toString(), _copyValue(nested)),
        ),
      );
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_copyValue));
    }
    return value;
  }

  static String? _findProhibitedClaim(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (prohibitedClaims.contains(key)) {
          return key;
        }
        final nested = _findProhibitedClaim(entry.value);
        if (nested != null) {
          return nested;
        }
      }
    }
    if (value is List) {
      for (final item in value) {
        final nested = _findProhibitedClaim(item);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }
}
