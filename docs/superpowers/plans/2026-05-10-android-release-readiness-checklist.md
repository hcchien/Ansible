# Android Release Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Ansible's Android app from generated scaffold to a beta-ready build that can be installed, smoke-tested, and prepared for Play Store submission.

**Architecture:** Treat Android as a first-class Flutter target, not a generated afterthought. First make the project compile, then replace template identity/assets/signing, then verify platform behavior for backup policy, secure identity storage, networking, i18n, and release builds.

**Tech Stack:** Flutter, Dart, Android Gradle Plugin, Kotlin, Android Manifest, adaptive launcher icons, Android signing configs, Play Store release checklist.

---

## Current Status Snapshot

Generated Android scaffold exists under `ansible_node/app/android/`.

Verified today:
- `flutter analyze`: passes.
- `flutter test test/backup_policy_service_test.dart test/home_shell_sync_test.dart test/app_i18n_coverage_test.dart`: passes, 15 tests.
- `flutter build apk --debug`: passes after adding a minimal Android plugin shell for `ansible_core/did`.

Known release blockers:
- Android app label is still `ansible_node`.
- Android launcher icon is still the Flutter template icon.
- Release signing uses debug signing config.
- No Android device smoke test has been completed.

Known non-blocking scaffold state:
- Android application id and namespace are currently `io.trisaura.ansible_node`.
- Android backup policy is already wired to `noBackupFilesDir` through `ansible_node/backup_policy`.
- `assets/brand/ansible_app_icon.svg` exists and can be used as the Android icon source.

---

### Task 1: Unblock Android Gradle Build

**Files:**
- Modify: `ansible_core/did/pubspec.yaml`
- Create or modify: `ansible_core/did/android/build.gradle.kts`
- Create or modify: `ansible_core/did/android/src/main/AndroidManifest.xml`
- Create or modify: `ansible_core/did/android/src/main/kotlin/io/trisaura/ansible_did/AnsibleDidPlugin.kt`
- Test: `ansible_node/app/test/android_release_readiness_test.dart`

- [x] **Step 1: Write failing static test for Android DID plugin packaging**

Create `ansible_node/app/test/android_release_readiness_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ansible_did has Android plugin files when declared as Android plugin', () {
    final pubspec = File('../../ansible_core/did/pubspec.yaml').readAsStringSync();

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
  });
}
```

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
```

Expected result: FAIL because `ansible_core/did/android/` does not exist.

- [x] **Step 2: Add minimal Android plugin shell for `ansible_did`**

Create `ansible_core/did/android/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.trisaura.ansible_did"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}
```

Create `ansible_core/did/android/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" />
```

Create `ansible_core/did/android/src/main/kotlin/io/trisaura/ansible_did/AnsibleDidPlugin.kt`:

```kotlin
package io.trisaura.ansible_did

import io.flutter.embedding.engine.plugins.FlutterPlugin

class AnsibleDidPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
```

- [x] **Step 3: Verify Android build unblocks**

Run:

```bash
cd ansible_node/app
flutter pub get
flutter test test/android_release_readiness_test.dart
flutter build apk --debug
```

Expected result:
- Test passes.
- `build/app/outputs/flutter-apk/app-debug.apk` is produced.

### Task 2: Product Identity And Manifest Hygiene

**Files:**
- Modify: `ansible_node/app/android/app/src/main/AndroidManifest.xml`
- Modify: `ansible_node/app/android/app/build.gradle.kts`
- Test: `ansible_node/app/test/android_release_readiness_test.dart`

- [ ] **Step 1: Add failing test for release identity**

Append this test to `ansible_node/app/test/android_release_readiness_test.dart`:

```dart
test('android app uses release product identity instead of Flutter template identity', () {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  expect(manifest, contains('android:label="@string/app_name"'));
  expect(manifest, isNot(contains('android:label="ansible_node"')));
  expect(gradle, contains('applicationId = "io.trisaura.ansible"'));
  expect(gradle, isNot(contains('Specify your own unique Application ID')));
});
```

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
```

Expected result: FAIL because label is `ansible_node`, app id is `io.trisaura.ansible_node`, and generated comments remain.

- [ ] **Step 2: Set manifest label to resource**

Change `ansible_node/app/android/app/src/main/AndroidManifest.xml` application label:

```xml
android:label="@string/app_name"
```

Create `ansible_node/app/android/app/src/main/res/values/strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Ansible</string>
</resources>
```

- [ ] **Step 3: Set production application id**

Change `ansible_node/app/android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    applicationId = "io.trisaura.ansible"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

Remove the generated application id comment from the same block.

- [ ] **Step 4: Verify identity changes**

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
flutter build apk --debug
```

Expected result:
- Test passes.
- Debug APK still builds.

### Task 3: Android Launcher Icon

**Files:**
- Modify: `ansible_node/app/pubspec.yaml`
- Modify: `ansible_node/app/android/app/src/main/res/mipmap-*/ic_launcher.png`
- Create: `ansible_node/app/android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Create: `ansible_node/app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Test: `ansible_node/app/test/android_release_readiness_test.dart`

- [ ] **Step 1: Add failing icon test**

Append this test to `ansible_node/app/test/android_release_readiness_test.dart`:

```dart
test('android launcher icon is not the generated Flutter template only', () {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final adaptiveIcon = File(
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  );
  final foreground = File(
    'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
  );

  expect(pubspec, contains('flutter_launcher_icons:'));
  expect(pubspec, contains('assets/brand/ansible_app_icon.svg'));
  expect(adaptiveIcon.existsSync(), isTrue);
  expect(foreground.existsSync(), isTrue);
});
```

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
```

Expected result: FAIL because adaptive icon resources and icon generation config are not present.

- [ ] **Step 2: Add icon generator config**

Add to `ansible_node/app/pubspec.yaml` under `dev_dependencies`:

```yaml
  flutter_launcher_icons: ^0.14.4
```

Add a root-level config block in `ansible_node/app/pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: assets/brand/ansible_app_icon.svg
  adaptive_icon_background: "#F6F2EA"
  adaptive_icon_foreground: assets/brand/ansible_app_icon.svg
  min_sdk_android: 23
```

- [ ] **Step 3: Generate Android launcher assets**

Run:

```bash
cd ansible_node/app
flutter pub get
dart run flutter_launcher_icons
```

Expected result: Android launcher PNGs and adaptive icon resources are regenerated from `assets/brand/ansible_app_icon.svg`.

- [ ] **Step 4: Verify icon assets**

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
flutter build apk --debug
```

Expected result:
- Icon test passes.
- Debug APK builds with generated launcher assets.

### Task 4: Release Signing Configuration

**Files:**
- Modify: `ansible_node/app/android/app/build.gradle.kts`
- Modify: `ansible_node/app/android/.gitignore`
- Create local-only: `ansible_node/app/android/key.properties`
- Test: `ansible_node/app/test/android_release_readiness_test.dart`

- [ ] **Step 1: Add failing signing test**

Append this test to `ansible_node/app/test/android_release_readiness_test.dart`:

```dart
test('android release build does not use debug signing config', () {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final gitignore = File('android/.gitignore').readAsStringSync();

  expect(gradle, contains('create("release")'));
  expect(gradle, contains('storeFile = keystoreProperties["storeFile"]'));
  expect(gradle, contains('signingConfig = signingConfigs.getByName("release")'));
  expect(gradle, isNot(contains('signingConfig = signingConfigs.getByName("debug")')));
  expect(gitignore, contains('key.properties'));
  expect(gitignore, contains('**/*.jks'));
});
```

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
```

Expected result: FAIL because release still uses debug signing.

- [ ] **Step 2: Load signing properties in Gradle**

Add near the top of `ansible_node/app/android/app/build.gradle.kts` after `plugins`:

```kotlin
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
```

Add inside `android { ... }` before `buildTypes`:

```kotlin
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String?
        keyPassword = keystoreProperties["keyPassword"] as String?
        storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
        storePassword = keystoreProperties["storePassword"] as String?
    }
}
```

Change release build type:

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

- [ ] **Step 3: Create local signing file outside git**

Create `ansible_node/app/android/key.properties` locally with this shape:

```properties
storePassword=replace-with-local-password
keyPassword=replace-with-local-password
keyAlias=ansible
storeFile=../ansible-release.jks
```

Keep `key.properties`, `*.jks`, `*.keystore` ignored by `ansible_node/app/android/.gitignore`.

- [ ] **Step 4: Verify release signing config**

Run:

```bash
cd ansible_node/app
flutter test test/android_release_readiness_test.dart
flutter build appbundle --release
```

Expected result:
- Signing test passes.
- Release AAB builds when local signing secrets exist.

### Task 5: Android Platform Behavior Smoke Tests

**Files:**
- Test with existing app on Android device or emulator.
- Record results in this plan.

- [ ] **Step 1: Install debug APK on Android**

Run:

```bash
cd ansible_node/app
flutter devices
flutter install -d <android-device-id>
```

Expected result: App installs on an Android device or emulator.

- [ ] **Step 2: Smoke test first-run identity flow**

Manual checks:
- App opens without crash.
- Account creation can complete.
- Secure identity persists after force quit and relaunch.
- App does not ask the user to recreate identity after relaunch.

- [ ] **Step 3: Smoke test sync configuration**

Manual checks:
- Relay settings screen renders in selected language.
- User can add a relay server URL.
- Manual sync without a relay shows the setup prompt.
- Manual sync with a relay attempts network sync and shows success/failure status.

- [ ] **Step 4: Smoke test notes/discussions layout**

Manual checks:
- Note editor title field accepts input.
- Note editor style controls apply to selected text.
- Discussion tabs do not wrap awkwardly in English, Traditional Chinese, Japanese, German, Korean, Spanish, French, or Portuguese.
- Public/private controls are large enough to tap comfortably.

### Task 6: Play Store Submission Gate

**Files:**
- Create: `docs/superpowers/specs/2026-05-10-android-play-store-submission.md`

- [ ] **Step 1: Document Play Store metadata**

Create `docs/superpowers/specs/2026-05-10-android-play-store-submission.md`:

```markdown
# Android Play Store Submission Notes

## App Identity
- App name: Ansible
- Package name: io.trisaura.ansible
- Category: Social or Productivity, final choice pending product positioning.

## Required Store Assets
- App icon: generated from assets/brand/ansible_app_icon.svg.
- Feature graphic: 1024 x 500.
- Phone screenshots: at least 2.
- Tablet screenshots: optional for first beta unless tablet support is claimed.

## Data Safety Draft
- Account identity is stored locally.
- Canonical local content may be backed up by OS backup.
- Reconstructable relay/Nostr mirror caches are stored in no-backup storage.
- Public posts may be distributed to configured relay/forum/Nostr targets.
- Private content must not be federated.

## Pre-Submission Verification
- flutter analyze passes.
- flutter test release-readiness and core app tests pass.
- flutter build appbundle --release passes with production signing.
- Android device smoke test is completed.
```

- [ ] **Step 2: Verify submission doc exists**

Run:

```bash
test -f docs/superpowers/specs/2026-05-10-android-play-store-submission.md
```

Expected result: command exits with code 0.

---

## Acceptance Gates

- [ ] `flutter analyze` passes from `ansible_node/app`.
- [ ] `flutter test test/android_release_readiness_test.dart test/backup_policy_service_test.dart test/home_shell_sync_test.dart test/app_i18n_coverage_test.dart` passes.
- [ ] `flutter build apk --debug` passes.
- [ ] `flutter build appbundle --release` passes with local signing secrets.
- [ ] Android debug APK installs on a real Android device or emulator.
- [ ] First-run identity, sync settings, notes, discussions, language selection, and backup policy smoke tests are complete.

## Self-Review

Spec coverage:
- Android compile blocker is covered by Task 1.
- Product identity is covered by Task 2.
- Brand icon is covered by Task 3.
- Release signing is covered by Task 4.
- Runtime QA is covered by Task 5.
- Store submission materials are covered by Task 6.

Placeholder scan:
- Every task has concrete files, commands, and expected results.
- Manual checks are explicit and observable.
