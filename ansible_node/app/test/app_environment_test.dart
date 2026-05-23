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
    expect(AppEnvironment.allowInsecureIdentityFallback, isTrue);
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
}
