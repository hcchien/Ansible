import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for the on-simulator screenshot harness. Each `takeScreenshot(name)`
/// call in integration_test/screens_tour.dart streams PNG bytes back here; we
/// write them under design/current-screens/ in the repo so they can be dropped
/// straight into Claude design for style iteration. `SCREENSHOT_OUTPUT_DIR`
/// overrides that location for export-only capture sets.
Future<void> main() async {
  final outDir = Directory(
    Platform.environment['SCREENSHOT_OUTPUT_DIR'] ??
        '../../design/current-screens',
  );
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('${outDir.path}/$name.png');
      file.writeAsBytesSync(bytes);
      stdout.writeln('saved ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
