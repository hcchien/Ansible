import 'package:ansible_node/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the local development environment', () {
    expect(AppEnvironment.rawName, 'dev');
    expect(AppEnvironment.name, AppEnvironmentName.dev);
    expect(AppEnvironment.isProduction, isFalse);
    expect(AppEnvironment.defaultRelayBaseUrl, 'http://127.0.0.1:4001');
    expect(AppEnvironment.issuerBaseUrl, 'http://localhost:4002');
    expect(AppEnvironment.atProtoBaseUrl, AppEnvironment.defaultRelayBaseUrl);
    expect(AppEnvironment.allowInsecureSigningFallback, isFalse);
    expect(AppEnvironment.allowInsecureIdentityFallback, isFalse);
    expect(AppEnvironment.defaultHandleSuffix, 'user');
    expect(AppEnvironment.resetLocalIdentityOnStart, isFalse);
  });

  test('does not block local endpoints outside production', () {
    final issues = AppEnvironment.productionReadinessIssues(
      environmentName: AppEnvironmentName.staging,
      relayBaseUrl: 'http://127.0.0.1:4001',
      issuerBaseUrl: 'http://localhost:4002',
      atProtoBaseUrl: 'http://localhost:4001',
      allowInsecureSigningFallback: true,
      allowInsecureIdentityFallback: true,
      iosBundleIdentifier: 'com.example.ansibleNode',
      androidApplicationId: 'com.example.ansibleNode',
    );

    expect(issues, isEmpty);
  });

  test('flags unsafe production endpoint and signing settings', () {
    final issues = AppEnvironment.productionReadinessIssues(
      environmentName: AppEnvironmentName.prod,
      relayBaseUrl: 'http://127.0.0.1:4001',
      issuerBaseUrl: 'http://localhost:4002',
      atProtoBaseUrl: 'http://relay.local',
      allowInsecureSigningFallback: true,
      allowInsecureIdentityFallback: true,
      iosBundleIdentifier: 'com.example.ansibleNode',
      androidApplicationId: 'com.example.ansibleNode',
    );

    expect(
      issues,
      contains('ANSIBLE_RELAY_BASE_URL must be https and non-local.'),
    );
    expect(
      issues,
      contains('ANSIBLE_ISSUER_BASE_URL must be https and non-local.'),
    );
    expect(
      issues,
      contains('ANSIBLE_ATPROTO_BASE_URL must be https and non-local.'),
    );
    expect(
      issues,
      contains('ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK must be false.'),
    );
    expect(
      issues,
      contains('ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK must be false.'),
    );
    expect(issues, contains('iOS bundle identifier must not use com.example.'));
    expect(
      issues,
      contains('Android application id must not use com.example.'),
    );
  });

  test('flags private network HTTPS endpoints in production', () {
    final issues = AppEnvironment.productionReadinessIssues(
      environmentName: AppEnvironmentName.prod,
      relayBaseUrl: 'https://192.168.1.20',
      issuerBaseUrl: 'https://10.0.0.8',
      atProtoBaseUrl: 'https://[fd00::1]',
      allowInsecureSigningFallback: false,
      allowInsecureIdentityFallback: false,
      iosBundleIdentifier: 'io.trisaura.elix',
      androidApplicationId: 'io.trisaura.elix',
    );

    expect(
      issues,
      contains('ANSIBLE_RELAY_BASE_URL must be https and non-local.'),
    );
    expect(
      issues,
      contains('ANSIBLE_ISSUER_BASE_URL must be https and non-local.'),
    );
    expect(
      issues,
      contains('ANSIBLE_ATPROTO_BASE_URL must be https and non-local.'),
    );
  });

  test(
    'validateProductionReadiness fails fast for unsafe production config',
    () {
      expect(
        () => AppEnvironment.validateProductionReadiness(
          environmentName: AppEnvironmentName.prod,
          relayBaseUrl: 'http://127.0.0.1:4001',
          issuerBaseUrl: 'http://localhost:4002',
          atProtoBaseUrl: 'http://localhost:4001',
          allowInsecureSigningFallback: false,
          allowInsecureIdentityFallback: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Production configuration is not ready'),
          ),
        ),
      );
    },
  );

  test('runtime readiness blocks release builds that default to dev', () {
    final issues = AppEnvironment.runtimeReadinessIssues(
      environmentName: AppEnvironmentName.dev,
      isReleaseBuild: true,
      usesDevelopmentRustBridge: false,
      hasRealRustBridge: true,
    );

    expect(
      issues,
      contains('ANSIBLE_APP_ENV must be staging or prod for release builds.'),
    );
  });

  test('runtime readiness blocks production with development Rust bridge', () {
    final issues = AppEnvironment.runtimeReadinessIssues(
      environmentName: AppEnvironmentName.prod,
      relayBaseUrl: 'https://relay.elix.cool',
      issuerBaseUrl: 'https://issuer.elix.cool',
      atProtoBaseUrl: 'https://bsky.social',
      allowInsecureSigningFallback: false,
      allowInsecureIdentityFallback: false,
      isReleaseBuild: true,
      usesDevelopmentRustBridge: true,
      hasRealRustBridge: false,
      iosBundleIdentifier: 'io.trisaura.elix',
      androidApplicationId: 'io.trisaura.elix',
    );

    expect(
      issues,
      contains('Rust bridge must not be the development fallback.'),
    );
    expect(
      issues,
      contains('ANSIBLE_USES_REAL_RUST_BRIDGE must be true for prod builds.'),
    );
  });
}
