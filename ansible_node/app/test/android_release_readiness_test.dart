import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ansible_did has Android plugin files when declared as Android plugin',
    () {
      final pubspec = File(
        '../../ansible_core/did/pubspec.yaml',
      ).readAsStringSync();

      expect(pubspec, contains('android:'));
      expect(Directory('../../ansible_core/did/android').existsSync(), isTrue);
      expect(
        File('../../ansible_core/did/android/build.gradle.kts').existsSync(),
        isTrue,
      );
      expect(
        File(
          '../../ansible_core/did/android/src/main/AndroidManifest.xml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '../../ansible_core/did/android/src/main/kotlin/io/trisaura/ansible_did/AnsibleDidPlugin.kt',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('android app uses the registered Google Play identity', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:label="@string/app_name"'));
    expect(gradle, contains('applicationId = "com.reviz.elix"'));
    expect(strings, contains('<string name="app_name">Elix</string>'));
  });

  test('android release build requires a production signing key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final gitignore = File('android/.gitignore').readAsStringSync();

    expect(gradle, contains('create("release")'));
    expect(
      gradle,
      contains('signingConfig = signingConfigs.getByName("release")'),
    );
    expect(
      gradle,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(gitignore, contains('key.properties'));
    expect(gitignore, contains('**/*.jks'));
  });
}
