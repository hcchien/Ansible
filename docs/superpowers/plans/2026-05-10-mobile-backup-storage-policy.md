# Mobile Backup Storage Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split mobile storage into backup-eligible canonical data and no-backup remote mirror/cache data so iOS iCloud Backup and Android Auto Backup do not upload reconstructable federation payloads.

**Architecture:** Keep the existing Drift `ansible.db` in application support as the canonical local store. Add a platform-backed `BackupPolicyService` that prepares a `RemoteMirrorCache` directory excluded from iOS backup and placed under Android `noBackupFilesDir`; future relay/Nostr read caches should use this directory. Android also gets explicit backup XML rules so accidental future files/databases named as remote mirror cache stay excluded.

**Implementation note:** Native no-backup setup is best-effort. If a platform has no `ansible_node/backup_policy` bridge yet, app startup falls back to `Application Support/RemoteMirrorCache` instead of crashing; canonical data still stays in the existing backup-eligible app support directory.

**Tech Stack:** Flutter/Dart, `path_provider`, `MethodChannel`, iOS Swift `URLResourceValues.isExcludedFromBackup`, Android Kotlin `noBackupFilesDir`, Android backup XML.

---

### Task 1: Dart Backup Policy Service

**Files:**
- Create: `ansible_node/app/lib/services/backup_policy_service.dart`
- Create: `ansible_node/app/test/backup_policy_service_test.dart`
- Modify: `ansible_node/app/lib/main.dart`

- [x] **Step 1: Write failing tests**

Create `test/backup_policy_service_test.dart` with tests that mock `ansible_node/backup_policy` and verify:

```dart
testWidgets('prepareStorage asks native platform for remote mirror no-backup path', (tester) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(BackupPolicyService.channel, (call) async {
    expect(call.method, 'prepareRemoteMirrorDirectory');
    expect(call.arguments, {'name': 'RemoteMirrorCache'});
    return '/tmp/ansible-no-backup/RemoteMirrorCache';
  });

  final service = BackupPolicyService(
    applicationSupportDirectory: () async => Directory('/tmp/ansible-support'),
    useNativeNoBackupDirectory: true,
  );

  final paths = await service.prepareStorage();

  expect(paths.canonicalDirectory.path, '/tmp/ansible-support');
  expect(paths.remoteMirrorDirectory.path, '/tmp/ansible-no-backup/RemoteMirrorCache');
});
```

Run: `flutter test test/backup_policy_service_test.dart`
Expected: FAIL because `BackupPolicyService` does not exist.

- [x] **Step 2: Implement service**

Create `BackupPolicyService` with:

```dart
class BackupPolicyPaths {
  const BackupPolicyPaths({
    required this.canonicalDirectory,
    required this.remoteMirrorDirectory,
  });

  final Directory canonicalDirectory;
  final Directory remoteMirrorDirectory;
}

class BackupPolicyService {
  static const channel = MethodChannel('ansible_node/backup_policy');
  static const remoteMirrorDirectoryName = 'RemoteMirrorCache';

  BackupPolicyService({
    Future<Directory> Function()? applicationSupportDirectory,
    this.useNativeNoBackupDirectory = true,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _applicationSupportDirectory;
  final bool useNativeNoBackupDirectory;

  Future<BackupPolicyPaths> prepareStorage() async {
    final canonical = await _applicationSupportDirectory();
    await canonical.create(recursive: true);
    final remote = useNativeNoBackupDirectory
        ? Directory(await channel.invokeMethod<String>(
              'prepareRemoteMirrorDirectory',
              {'name': remoteMirrorDirectoryName},
            ) ??
            canonical.path)
        : Directory(p.join(canonical.path, remoteMirrorDirectoryName));
    await remote.create(recursive: true);
    return BackupPolicyPaths(
      canonicalDirectory: canonical,
      remoteMirrorDirectory: remote,
    );
  }
}
```

- [x] **Step 3: Wire app startup**

Modify `main.dart` so startup calls:

```dart
final storagePaths = await BackupPolicyService().prepareStorage();
final db = await _openAppDatabase(storagePaths: storagePaths);
```

and `_openAppDatabase` uses `storagePaths.canonicalDirectory`.

- [x] **Step 4: Verify**

Run: `flutter test test/backup_policy_service_test.dart`
Expected: PASS.

### Task 2: iOS Native No-Backup Directory

**Files:**
- Modify: `ansible_node/app/ios/Runner/AppDelegate.swift`
- Test: `ansible_node/app/test/backup_policy_service_test.dart`

- [x] **Step 1: Write failing static test**

Add a test that reads `ios/Runner/AppDelegate.swift` and expects:

```dart
expect(source, contains('FlutterMethodChannel(name: "ansible_node/backup_policy"'));
expect(source, contains('prepareRemoteMirrorDirectory'));
expect(source, contains('isExcludedFromBackup = true'));
```

Run: `flutter test test/backup_policy_service_test.dart`
Expected: FAIL until the Swift channel is added.

- [x] **Step 2: Implement Swift channel**

In `AppDelegate.swift`, after plugin registration, create a `FlutterMethodChannel` named `ansible_node/backup_policy`. For `prepareRemoteMirrorDirectory`, create `Application Support/<name>`, set `URLResourceValues.isExcludedFromBackup = true`, and return the absolute path. Return `FlutterMethodNotImplemented` for unknown methods.

- [x] **Step 3: Verify**

Run: `flutter test test/backup_policy_service_test.dart`
Expected: PASS.

### Task 3: Android No-Backup Directory And Backup Rules

**Files:**
- Create/modify: `ansible_node/app/android/app/src/main/AndroidManifest.xml`
- Create/modify: `ansible_node/app/android/app/src/main/kotlin/.../MainActivity.kt`
- Create: `ansible_node/app/android/app/src/main/res/xml/backup_rules.xml`
- Create: `ansible_node/app/android/app/src/main/res/xml/data_extraction_rules.xml`
- Test: `ansible_node/app/test/backup_policy_service_test.dart`

- [x] **Step 1: Write failing static tests**

Add tests that verify:

```dart
expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
expect(mainActivity, contains('noBackupFilesDir'));
expect(mainActivity, contains('prepareRemoteMirrorDirectory'));
expect(backupRules, contains('RemoteMirrorCache'));
expect(dataExtractionRules, contains('RemoteMirrorCache'));
```

Run: `flutter test test/backup_policy_service_test.dart`
Expected: FAIL because Android platform files are missing or not configured.

- [x] **Step 2: Generate Android shell if missing**

Run from `ansible_node/app`:

```bash
flutter create --platforms=android --org io.trisaura .
```

Expected: `android/` exists and Flutter project metadata remains valid.

- [x] **Step 3: Implement Android channel**

In `MainActivity.kt`, register `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ansible_node/backup_policy")`. For `prepareRemoteMirrorDirectory`, create `File(noBackupFilesDir, name)` and return `absolutePath`.

- [x] **Step 4: Add backup XML rules**

In `AndroidManifest.xml` application tag, add:

```xml
android:fullBackupContent="@xml/backup_rules"
android:dataExtractionRules="@xml/data_extraction_rules"
```

Create XML rules excluding `RemoteMirrorCache/` from cloud backup and device transfer:

```xml
<full-backup-content>
    <exclude domain="file" path="RemoteMirrorCache/" />
</full-backup-content>
```

and:

```xml
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="file" path="RemoteMirrorCache/" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="file" path="RemoteMirrorCache/" />
    </device-transfer>
</data-extraction-rules>
```

- [x] **Step 5: Verify**

Run:

```bash
flutter test test/backup_policy_service_test.dart
flutter analyze
```

Expected: both pass.

### Task 4: Regression Sweep

**Files:**
- Existing tests only.

- [x] **Step 1: Run affected tests**

Run:

```bash
flutter test test/backup_policy_service_test.dart test/home_shell_sync_test.dart test/app_i18n_coverage_test.dart
```

Expected: all pass.

- [x] **Step 2: Summarize follow-up**

Record in the final response that the no-backup path exists but relay/Nostr read caches still need to migrate to `BackupPolicyPaths.remoteMirrorDirectory` when those caches are materialized as files or a separate DB.

---

## Self-Review

- Spec coverage: iOS iCloud backup exclusion, Android Auto Backup exclusion, canonical DB backup eligibility, and remote mirror no-backup path are covered.
- Placeholder scan: no placeholder implementation steps remain.
- Type consistency: `BackupPolicyService.prepareStorage`, `BackupPolicyPaths.canonicalDirectory`, and `BackupPolicyPaths.remoteMirrorDirectory` are consistent across tests and code.
