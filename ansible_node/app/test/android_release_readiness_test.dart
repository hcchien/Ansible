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
}
