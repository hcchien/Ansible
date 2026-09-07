import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'file-domain SQLite and sidecars excluded in legacy, cloud and transfer backups',
    () {
      final legacy = XmlDocument.parse(
        File(
          'android/app/src/main/res/xml/backup_rules.xml',
        ).readAsStringSync(),
      );
      final modern = XmlDocument.parse(
        File(
          'android/app/src/main/res/xml/data_extraction_rules.xml',
        ).readAsStringSync(),
      );
      final policies = [
        legacy.rootElement,
        modern.findAllElements('cloud-backup').single,
        modern.findAllElements('device-transfer').single,
      ];
      for (final policy in policies) {
        for (final path in ['ansible.db', 'ansible.db-wal', 'ansible.db-shm']) {
          expect(
            policy
                .findElements('exclude')
                .any(
                  (entry) =>
                      entry.getAttribute('domain') == 'file' &&
                      entry.getAttribute('path') == path,
                ),
            true,
            reason:
                '${policy.name}: $path must match application support files directory',
          );
        }
      }
    },
  );
}
