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
    'documentNumber',
    'passportNumber',
    'passportLocalUniqueId',
    'passportUid',
    'passport_uid',
    'nationalIdHash',
    'national_id_hash',
    'passportNumberHash',
    'passport_number_hash',
    'rawMrz',
    'rawMRZ',
    'dg1',
    'dg2',
    'sod',
    'faceImage',
  };

  final Map<String, Object?> json;
  final String id;
  final List<String> types;
  final String issuerDid;
  final String holderDid;
  final DateTime validFrom;
  final DateTime validUntil;
  final Map<String, Object?> claims;
  final List<Map<String, Object?>> credentialStatus;
  final Map<String, Object?>? proof;
  final String? compactJwt;

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
    required this.compactJwt,
  });

  factory TrisAuraCredential.fromJson(Map<String, Object?> json) {
    final compact = json['compact'];
    final wrapped = json['vc'];
    if (json['format'] == 'jwt_vc_json' &&
        compact is String &&
        wrapped is Map) {
      return TrisAuraCredential._fromCredentialJson(
        Map<String, Object?>.from(wrapped),
        compactJwt: compact,
      );
    }
    return TrisAuraCredential._fromCredentialJson(json);
  }

  factory TrisAuraCredential._fromCredentialJson(
    Map<String, Object?> json, {
    String? compactJwt,
  }) {
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
      validFrom: DateTime.parse(
        _requiredTemporalString(json, 'validFrom', 'issuanceDate'),
      ).toUtc(),
      validUntil: DateTime.parse(
        _requiredTemporalString(json, 'validUntil', 'expirationDate'),
      ).toUtc(),
      claims: Map<String, Object?>.unmodifiable(subject),
      credentialStatus: _credentialStatusList(json),
      proof: _optionalMap(json, 'proof'),
      compactJwt: compactJwt,
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

  static String _requiredTemporalString(
    Map<String, Object?> json,
    String currentKey,
    String legacyKey,
  ) {
    final current = json[currentKey];
    if (current is String && current.isNotEmpty) return current;
    final legacy = json[legacyKey];
    if (legacy is String && legacy.isNotEmpty) return legacy;
    throw TrisAuraCredentialException(
      'invalid_credential',
      'Credential field "$currentKey" or "$legacyKey" must be a non-empty string.',
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

  static List<Map<String, Object?>> _credentialStatusList(
    Map<String, Object?> json,
  ) {
    final value = json['credentialStatus'];
    if (value == null) return const [];
    if (value is Map) {
      return [Map<String, Object?>.unmodifiable(Map.from(value))];
    }
    if (value is List && value.every((entry) => entry is Map)) {
      return List<Map<String, Object?>>.unmodifiable(
        value.map(
          (entry) => Map<String, Object?>.unmodifiable(Map.from(entry as Map)),
        ),
      );
    }
    throw TrisAuraCredentialException(
      'invalid_credential',
      'Credential field "credentialStatus" must be an object or object list.',
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
