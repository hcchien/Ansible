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

  /// Base URL of the AppView timeline service (scalable following feed). When
  /// [useAppViewFeed] is true, the Following feed is served from here instead of
  /// filtering the relay global delta locally.
  static const appViewBaseUrl = String.fromEnvironment(
    'ANSIBLE_APPVIEW_BASE_URL',
    defaultValue: '',
  );

  static const useAppViewFeed = bool.fromEnvironment(
    'ANSIBLE_USE_APPVIEW_FEED',
    defaultValue: false,
  );

  /// When true (and the AppView feed is enabled), the Following feed is served
  /// from the reader's server-materialized home timeline (fan-out-on-write,
  /// `GET /api/v1/home`) instead of fan-out-on-read over the follow set.
  static const useAppViewHomeTimeline = bool.fromEnvironment(
    'ANSIBLE_USE_APPVIEW_HOME_TIMELINE',
    defaultValue: false,
  );

  static const resetLocalIdentityOnStart = bool.fromEnvironment(
    'ANSIBLE_RESET_LOCAL_IDENTITY_ON_START',
    defaultValue: false,
  );

  static const allowInsecureSigningFallback = bool.fromEnvironment(
    'ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK',
    defaultValue: false,
  );

  // Secure default: insecure identity fallback is DISABLED unless explicitly
  // opted-in at compile time. This ensures that staging and test builds do not
  // silently bypass hardware-backed key generation (Secure Enclave/StrongBox).
  // Set ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK=true (or the legacy alias
  // ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK=true) only in local dev environments.
  static const allowInsecureIdentityFallback =
      bool.hasEnvironment('ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK')
      ? bool.fromEnvironment('ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK')
      : bool.fromEnvironment(
          'ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK',
          defaultValue: false,
        );

  static const hasRealRustBridge = bool.fromEnvironment(
    'ANSIBLE_USES_REAL_RUST_BRIDGE',
    defaultValue: false,
  );

  static const defaultHandleSuffix = String.fromEnvironment(
    'ANSIBLE_DEFAULT_HANDLE_SUFFIX',
    defaultValue: 'user',
  );

  /// Public web frontend origin (forum). Legal / policy pages required for
  /// store submission live here (`/privacy`, `/terms`, `/about`,
  /// `/account-deletion`) and are opened from the in-app About screen.
  static const forumWebBaseUrl = String.fromEnvironment(
    'ANSIBLE_FORUM_WEB_BASE_URL',
    defaultValue: 'https://forum.elix.cool',
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

  static List<String> runtimeReadinessIssues({
    AppEnvironmentName? environmentName,
    String? relayBaseUrl,
    String? issuerBaseUrl,
    String? atProtoBaseUrl,
    bool? allowInsecureSigningFallback,
    bool? allowInsecureIdentityFallback,
    bool? isReleaseBuild,
    bool? usesDevelopmentRustBridge,
    bool? hasRealRustBridge,
    String? iosBundleIdentifier,
    String? androidApplicationId,
  }) {
    final envName = environmentName ?? name;
    final releaseBuild = isReleaseBuild ?? false;
    final devRustBridge = usesDevelopmentRustBridge ?? false;
    final realRustBridge =
        hasRealRustBridge ?? AppEnvironment.hasRealRustBridge;
    final issues = <String>[];

    if (releaseBuild && envName == AppEnvironmentName.dev) {
      issues.add('ANSIBLE_APP_ENV must be staging or prod for release builds.');
    }

    if ((releaseBuild || envName == AppEnvironmentName.prod) && devRustBridge) {
      issues.add('Rust bridge must not be the development fallback.');
    }

    if (envName == AppEnvironmentName.prod && !realRustBridge) {
      issues.add('ANSIBLE_USES_REAL_RUST_BRIDGE must be true for prod builds.');
    }

    issues.addAll(
      productionReadinessIssues(
        environmentName: envName,
        relayBaseUrl: relayBaseUrl,
        issuerBaseUrl: issuerBaseUrl,
        atProtoBaseUrl: atProtoBaseUrl,
        allowInsecureSigningFallback: allowInsecureSigningFallback,
        allowInsecureIdentityFallback: allowInsecureIdentityFallback,
        iosBundleIdentifier: iosBundleIdentifier,
        androidApplicationId: androidApplicationId,
      ),
    );

    return issues;
  }

  static void validateRuntimeReadiness({
    AppEnvironmentName? environmentName,
    String? relayBaseUrl,
    String? issuerBaseUrl,
    String? atProtoBaseUrl,
    bool? allowInsecureSigningFallback,
    bool? allowInsecureIdentityFallback,
    bool? isReleaseBuild,
    bool? usesDevelopmentRustBridge,
    bool? hasRealRustBridge,
    String? iosBundleIdentifier,
    String? androidApplicationId,
  }) {
    final issues = runtimeReadinessIssues(
      environmentName: environmentName,
      relayBaseUrl: relayBaseUrl,
      issuerBaseUrl: issuerBaseUrl,
      atProtoBaseUrl: atProtoBaseUrl,
      allowInsecureSigningFallback: allowInsecureSigningFallback,
      allowInsecureIdentityFallback: allowInsecureIdentityFallback,
      isReleaseBuild: isReleaseBuild,
      usesDevelopmentRustBridge: usesDevelopmentRustBridge,
      hasRealRustBridge: hasRealRustBridge,
      iosBundleIdentifier: iosBundleIdentifier,
      androidApplicationId: androidApplicationId,
    );
    if (issues.isEmpty) return;

    throw StateError('Runtime configuration is not ready: ${issues.join(' ')}');
  }

  static bool _isInsecureOrLocalEndpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return true;
    }

    final host = uri.host.toLowerCase();
    return uri.scheme.toLowerCase() != 'https' || _isPrivateOrLocalHost(host);
  }

  static bool _isPrivateOrLocalHost(String host) {
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '0.0.0.0' ||
        host == '::1') {
      return true;
    }

    if (host.startsWith('127.')) return true;
    if (host.startsWith('10.')) return true;
    if (host.startsWith('192.168.')) return true;
    if (host.startsWith('169.254.')) return true;

    final ipv4Parts = host.split('.');
    if (ipv4Parts.length == 4) {
      final first = int.tryParse(ipv4Parts[0]);
      final second = int.tryParse(ipv4Parts[1]);
      if (first == 172 && second != null && second >= 16 && second <= 31) {
        return true;
      }
      if (first == 100 && second != null && second >= 64 && second <= 127) {
        return true;
      }
    }

    final isIpv6 = host.contains(':');
    return isIpv6 &&
        (host.startsWith('fc') ||
            host.startsWith('fd') ||
            host.startsWith('fe80:'));
  }

  static bool _isExampleIdentifier(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    return value.toLowerCase().startsWith('com.example');
  }
}
