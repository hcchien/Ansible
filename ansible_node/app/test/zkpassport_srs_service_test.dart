import 'dart:io';

import 'package:ansible_node/services/zkpassport_srs_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late HttpServer server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('elix-srs-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  test('downloads, verifies, reports progress, and deletes the SRS', () async {
    final bytes = List<int>.generate(4096, (index) => index % 251);
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final progress = <int>[];
    final service = ZkPassportSrsService(
      source: Uri.parse('http://127.0.0.1:${server.port}/21.srs'),
      expectedSha256: sha256.convert(bytes).toString(),
      expectedBytes: bytes.length,
      directoryProvider: () async => temp,
      onProgress: (received, _) => progress.add(received),
    );

    final path = await service.acquire();
    expect(await File(path).readAsBytes(), bytes);
    expect(progress, containsAllInOrder([0, bytes.length]));

    await service.release(path);
    expect(File(path).existsSync(), isFalse);
  });

  test('rejects a hash mismatch and removes partial files', () async {
    final bytes = List<int>.filled(128, 7);
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final service = ZkPassportSrsService(
      source: Uri.parse('http://127.0.0.1:${server.port}/21.srs'),
      expectedSha256: List<String>.filled(64, '0').join(),
      expectedBytes: bytes.length,
      directoryProvider: () async => temp,
    );

    await expectLater(service.acquire(), throwsA(isA<FormatException>()));
    expect(temp.listSync().whereType<File>(), isEmpty);
  });
}
