enum AppEnvironmentName {
  dev,
  staging,
  prod;

  static AppEnvironmentName parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'dev':
      case 'development':
        return AppEnvironmentName.dev;
      case 'staging':
      case 'stage':
        return AppEnvironmentName.staging;
      case 'prod':
      case 'production':
        return AppEnvironmentName.prod;
    }

    throw StateError('Unsupported ANSIBLE_APP_ENV: $value');
  }
}

class AppEnvironment {
  const AppEnvironment._();

  static const rawName = String.fromEnvironment(
    'ANSIBLE_APP_ENV',
    defaultValue: 'dev',
  );

  static AppEnvironmentName get name => AppEnvironmentName.parse(rawName);

  static bool get isProduction => name == AppEnvironmentName.prod;

  static const defaultRelayBaseUrl = String.fromEnvironment(
    'ANSIBLE_RELAY_BASE_URL',
    defaultValue: 'http://127.0.0.1:4001',
  );

  static const issuerBaseUrl = String.fromEnvironment(
    'ANSIBLE_ISSUER_BASE_URL',
    defaultValue: 'http://localhost:4002',
  );

  static const atProtoBaseUrl = String.fromEnvironment(
    'ANSIBLE_ATPROTO_BASE_URL',
    defaultValue: defaultRelayBaseUrl,
  );

  static const resetLocalIdentityOnStart = bool.fromEnvironment(
    'ANSIBLE_RESET_LOCAL_IDENTITY_ON_START',
    defaultValue: false,
  );

  static const allowInsecureSigningFallback = bool.fromEnvironment(
    'ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK',
    defaultValue: false,
  );

  static const allowInsecureIdentityFallback =
      bool.hasEnvironment('ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK')
      ? bool.fromEnvironment('ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK')
      : bool.fromEnvironment(
          'ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK',
          defaultValue: true,
        );

  static const defaultHandleSuffix = String.fromEnvironment(
    'ANSIBLE_DEFAULT_HANDLE_SUFFIX',
    defaultValue: 'user',
  );

  static List<String> productionReadinessIssues({
    AppEnvironmentName? environmentName,
    String? relayBaseUrl,
    String? issuerBaseUrl,
    String? atProtoBaseUrl,
    bool? allowInsecureSigningFallback,
    bool? allowInsecureIdentityFallback,
    String? iosBundleIdentifier,
    String? androidApplicationId,
  }) {
    final envName = environmentName ?? name;
    if (envName != AppEnvironmentName.prod) {
      return const [];
    }

    final issues = <String>[];
    if (_isInsecureOrLocalEndpoint(relayBaseUrl ?? defaultRelayBaseUrl)) {
      issues.add('ANSIBLE_RELAY_BASE_URL must be https and non-local.');
    }
    if (_isInsecureOrLocalEndpoint(
      issuerBaseUrl ?? AppEnvironment.issuerBaseUrl,
    )) {
      issues.add('ANSIBLE_ISSUER_BASE_URL must be https and non-local.');
    }
    if (_isInsecureOrLocalEndpoint(
      atProtoBaseUrl ?? AppEnvironment.atProtoBaseUrl,
    )) {
      issues.add('ANSIBLE_ATPROTO_BASE_URL must be https and non-local.');
    }
    if (allowInsecureSigningFallback ??
        AppEnvironment.allowInsecureSigningFallback) {
      issues.add('ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK must be false.');
    }
    if (allowInsecureIdentityFallback ??
        AppEnvironment.allowInsecureIdentityFallback) {
      issues.add('ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK must be false.');
    }
    if (_isExampleIdentifier(iosBundleIdentifier)) {
      issues.add('iOS bundle identifier must not use com.example.');
    }
    if (_isExampleIdentifier(androidApplicationId)) {
      issues.add('Android application id must not use com.example.');
    }
    return issues;
  }

  static void validateProductionReadiness({
    AppEnvironmentName? environmentName,
    String? relayBaseUrl,
    String? issuerBaseUrl,
    String? atProtoBaseUrl,
    bool? allowInsecureSigningFallback,
    bool? allowInsecureIdentityFallback,
    String? iosBundleIdentifier,
    String? androidApplicationId,
  }) {
    final issues = productionReadinessIssues(
      environmentName: environmentName,
      relayBaseUrl: relayBaseUrl,
      issuerBaseUrl: issuerBaseUrl,
      atProtoBaseUrl: atProtoBaseUrl,
      allowInsecureSigningFallback: allowInsecureSigningFallback,
      allowInsecureIdentityFallback: allowInsecureIdentityFallback,
      iosBundleIdentifier: iosBundleIdentifier,
      androidApplicationId: androidApplicationId,
    );
    if (issues.isEmpty) {
      return;
    }

    throw StateError(
      'Production configuration is not ready: ${issues.join(' ')}',
    );
  }

  static bool _isInsecureOrLocalEndpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return true;
    }

    final host = uri.host.toLowerCase();
    return uri.scheme.toLowerCase() != 'https' ||
        host == 'localhost' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host.startsWith('127.');
  }

  static bool _isExampleIdentifier(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    return value.toLowerCase().startsWith('com.example');
  }
}
