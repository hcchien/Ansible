import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackupPolicyPaths {
  const BackupPolicyPaths({
    required this.canonicalDirectory,
    required this.remoteMirrorDirectory,
  });

  final Directory canonicalDirectory;
  final Directory remoteMirrorDirectory;
}

class BackupPolicyService {
  BackupPolicyService({
    Future<Directory> Function()? applicationSupportDirectory,
    this.useNativeNoBackupDirectory = true,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  static const channel = MethodChannel('ansible_node/backup_policy');
  static const remoteMirrorDirectoryName = 'RemoteMirrorCache';

  final Future<Directory> Function() _applicationSupportDirectory;
  final bool useNativeNoBackupDirectory;

  Future<BackupPolicyPaths> prepareStorage() async {
    final canonical = await _applicationSupportDirectory();
    await canonical.create(recursive: true);

    final remote = await _remoteMirrorDirectory(canonical);
    await remote.create(recursive: true);

    return BackupPolicyPaths(
      canonicalDirectory: canonical,
      remoteMirrorDirectory: remote,
    );
  }

  Future<Directory> _remoteMirrorDirectory(Directory canonical) async {
    if (useNativeNoBackupDirectory) {
      try {
        final nativePath = await channel.invokeMethod<String>(
          'prepareRemoteMirrorDirectory',
          {'name': remoteMirrorDirectoryName},
        );
        if (nativePath != null && nativePath.isNotEmpty) {
          return Directory(nativePath);
        }
      } on MissingPluginException {
        // Desktop/test runners may not have a native bridge yet.
      } on PlatformException {
        // Keep startup resilient; platform-specific failures should not block local data.
      }
    }

    return Directory(p.join(canonical.path, remoteMirrorDirectoryName));
  }
}
