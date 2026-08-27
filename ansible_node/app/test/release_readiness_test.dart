import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production config is explicit and fail-closed', () {
    final config =
        jsonDecode(File('config/production.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(config['ANSIBLE_APP_ENV'], 'prod');
    expect(config['ANSIBLE_USES_REAL_RUST_BRIDGE'], isTrue);
    expect(config['ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK'], isFalse);
    expect(config['ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK'], isFalse);
    expect(config['ANSIBLE_RESET_LOCAL_IDENTITY_ON_START'], isFalse);
    expect(config['ANSIBLE_USE_APPVIEW_FEED'], isTrue);
    expect(
      config['ANSIBLE_USE_APPVIEW_HOME_TIMELINE'],
      isFalse,
      reason: 'The app does not yet send the signed /api/v1/home headers.',
    );

    for (final key in const [
      'ANSIBLE_RELAY_BASE_URL',
      'ANSIBLE_ISSUER_BASE_URL',
      'ANSIBLE_ATPROTO_BASE_URL',
      'ANSIBLE_FORUM_WEB_BASE_URL',
    ]) {
      final uri = Uri.parse(config[key]! as String);
      expect(uri.scheme, 'https', reason: key);
      expect(uri.host, isNotEmpty, reason: key);
      expect(uri.host, isNot(anyOf('localhost', '127.0.0.1')), reason: key);
    }
  });

  test('TestFlight config is staging with remote HTTPS services', () {
    final config =
        jsonDecode(File('config/testflight.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(config['ANSIBLE_APP_ENV'], 'staging');
    expect(config['ANSIBLE_USES_REAL_RUST_BRIDGE'], isTrue);
    expect(config['ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK'], isFalse);
    expect(config['ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK'], isFalse);
    expect(config['ANSIBLE_USE_APPVIEW_FEED'], isTrue);
    expect(
      config['ANSIBLE_USE_APPVIEW_HOME_TIMELINE'],
      isFalse,
      reason: 'The app does not yet send the signed /api/v1/home headers.',
    );
    for (final key in const [
      'ANSIBLE_RELAY_BASE_URL',
      'ANSIBLE_ISSUER_BASE_URL',
      'ANSIBLE_ATPROTO_BASE_URL',
      'ANSIBLE_APPVIEW_BASE_URL',
      'ANSIBLE_FORUM_WEB_BASE_URL',
    ]) {
      final uri = Uri.parse(config[key]! as String);
      expect(uri.scheme, 'https', reason: key);
      expect(
        uri.host,
        anyOf('dev.elix.cool', endsWith('-dev.elix.cool')),
        reason: key,
      );
    }
  });

  test('mobile platforms use the registered production identity', () {
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    final ios = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(android, contains('applicationId = "com.reviz.elix"'));
    expect(ios, contains('PRODUCT_BUNDLE_IDENTIFIER = com.reviz.elix;'));
    expect(
      ios,
      anyOf(
        contains('DEVELOPMENT_TEAM = K3X2X4CL3H;'),
        contains('"DEVELOPMENT_TEAM[sdk=iphoneos*]" = K3X2X4CL3H;'),
      ),
    );
    expect(ios, isNot(contains('com.example.ansibleNode')));
    expect(
      ios,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;'),
    );

    final releaseEntitlements = File(
      'ios/Runner/RunnerRelease.entitlements',
    ).readAsStringSync();
    expect(releaseEntitlements, contains('<string>production</string>'));
    expect(releaseEntitlements, contains('webcredentials:dev.elix.cool'));
    expect(releaseEntitlements, contains('webcredentials:elix.cool'));

    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    expect(iosInfo, contains('<key>ITSAppUsesNonExemptEncryption</key>'));
    expect(
      iosInfo,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
  });

  test('desktop platforms use Elix production identity and naming', () {
    final macos = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final windows = File('windows/runner/Runner.rc').readAsStringSync();
    final linux = File('linux/CMakeLists.txt').readAsStringSync();

    expect(macos, contains('PRODUCT_BUNDLE_IDENTIFIER = com.reviz.elix'));
    expect(macos, contains('PRODUCT_NAME = Elix'));
    expect(macosProject, contains('DEVELOPMENT_TEAM = K3X2X4CL3H;'));
    expect(windows, contains('VALUE "ProductName", "Elix"'));
    expect(windows, contains('VALUE "OriginalFilename", "elix.exe"'));
    expect(linux, contains('set(BINARY_NAME "elix")'));
    expect(linux, contains('set(APPLICATION_ID "com.reviz.elix")'));
  });

  test('macOS release keeps secure-storage keychain access', () {
    final entitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();

    expect(entitlements, contains('<key>com.apple.security.app-sandbox</key>'));
    expect(entitlements, contains('<key>keychain-access-groups</key>'));
    expect(
      entitlements,
      contains(r'$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)'),
    );

    final info = File('macos/Runner/Info.plist').readAsStringSync();
    expect(
      info,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
  });
}
