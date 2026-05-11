import 'dart:io';

import 'package:ansible_node/services/backup_policy_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupPolicyService.channel, null);
  });

  test(
    'prepareStorage asks native platform for remote mirror no-backup path',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BackupPolicyService.channel, (call) async {
            expect(call.method, 'prepareRemoteMirrorDirectory');
            expect(call.arguments, {'name': 'RemoteMirrorCache'});
            return '/tmp/ansible-no-backup/RemoteMirrorCache';
          });

      final service = BackupPolicyService(
        applicationSupportDirectory: () async =>
            Directory('/tmp/ansible-support'),
        useNativeNoBackupDirectory: true,
      );

      final paths = await service.prepareStorage();

      expect(paths.canonicalDirectory.path, '/tmp/ansible-support');
      expect(
        paths.remoteMirrorDirectory.path,
        '/tmp/ansible-no-backup/RemoteMirrorCache',
      );
    },
  );

  test(
    'prepareStorage can fall back to application support for tests',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ansible-backup-test-',
      );
      addTearDown(() => root.delete(recursive: true));

      final service = BackupPolicyService(
        applicationSupportDirectory: () async => root,
        useNativeNoBackupDirectory: false,
      );

      final paths = await service.prepareStorage();

      expect(paths.canonicalDirectory.path, root.path);
      expect(
        paths.remoteMirrorDirectory.path,
        '${root.path}/RemoteMirrorCache',
      );
      expect(paths.remoteMirrorDirectory.existsSync(), isTrue);
    },
  );

  test(
    'prepareStorage falls back when native backup channel is unavailable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ansible-backup-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BackupPolicyService.channel, (call) async {
            throw MissingPluginException(
              'No backup policy channel registered.',
            );
          });

      final service = BackupPolicyService(
        applicationSupportDirectory: () async => root,
        useNativeNoBackupDirectory: true,
      );

      final paths = await service.prepareStorage();

      expect(paths.canonicalDirectory.path, root.path);
      expect(
        paths.remoteMirrorDirectory.path,
        '${root.path}/RemoteMirrorCache',
      );
      expect(paths.remoteMirrorDirectory.existsSync(), isTrue);
    },
  );

  test('ios runner registers backup policy channel', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(
      source,
      contains('FlutterMethodChannel(name: "ansible_node/backup_policy"'),
    );
    expect(source, contains('prepareRemoteMirrorDirectory'));
    expect(source, contains('isExcludedFromBackup = true'));
  });

  test('android runner excludes remote mirror cache from backup', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/io/trisaura/ansible_node/MainActivity.kt',
    ).readAsStringSync();
    final backupRules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final dataExtractionRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(mainActivity, contains('noBackupFilesDir'));
    expect(mainActivity, contains('prepareRemoteMirrorDirectory'));
    expect(backupRules, contains('RemoteMirrorCache'));
    expect(dataExtractionRules, contains('RemoteMirrorCache'));
  });
}
