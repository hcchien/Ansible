import 'dart:io';

import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

typedef ZkpSrsProgress = void Function(int receivedBytes, int totalBytes);
typedef ZkpSrsDirectoryProvider = Future<Directory> Function();

class ZkPassportSrsService implements ZkpSrsProvider {
  ZkPassportSrsService({
    this.onProgress,
    Uri? source,
    String? expectedSha256,
    int? expectedBytes,
    ZkpSrsDirectoryProvider? directoryProvider,
  }) : source = source ?? _source,
       expectedSha256 = expectedSha256 ?? _expectedSha256,
       expectedBytes = expectedBytes ?? _expectedBytes,
       directoryProvider = directoryProvider ?? getTemporaryDirectory;

  static final Uri _source = Uri.https('cdn.zkpassport.id', '/srs/21.srs');
  static const _expectedSha256 =
      '7d368f9342b99252a06249e46a3edfbda9aa2e9afb482bfe848245ab538c6996';
  static const _expectedBytes = 134217940;

  final ZkpSrsProgress? onProgress;
  final Uri source;
  final String expectedSha256;
  final int expectedBytes;
  final ZkpSrsDirectoryProvider directoryProvider;
  String? _leasedPath;

  @override
  Future<String> acquire() async {
    final leasedPath = _leasedPath;
    if (leasedPath != null && await File(leasedPath).exists()) {
      onProgress?.call(expectedBytes, expectedBytes);
      return leasedPath;
    }
    final directory = await directoryProvider();
    await directory.create(recursive: true);
    final destination = File('${directory.path}/elix-zkpassport-srs-21.local');
    final partial = File('${destination.path}.partial');
    await _deleteIfPresent(destination);
    await _deleteIfPresent(partial);

    final client = HttpClient()..autoUncompress = false;
    RandomAccessFile? output;
    try {
      final request = await client.getUrl(source);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'ZKPassport SRS download returned HTTP ${response.statusCode}.',
          uri: source,
        );
      }

      final digestSink = _DigestSink();
      final digestInput = sha256.startChunkedConversion(digestSink);
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      onProgress?.call(0, expectedBytes);
      await for (final chunk in response) {
        received += chunk.length;
        if (received > expectedBytes) {
          throw const FormatException(
            'ZKPassport SRS download exceeded the pinned size.',
          );
        }
        digestInput.add(chunk);
        await output.writeFrom(chunk);
        onProgress?.call(received, expectedBytes);
      }
      digestInput.close();
      await output.close();
      output = null;

      if (received != expectedBytes) {
        throw FormatException(
          'ZKPassport SRS size mismatch: expected $expectedBytes bytes, '
          'received $received.',
        );
      }
      final actualSha256 = digestSink.value?.toString();
      if (actualSha256 != expectedSha256) {
        throw const FormatException('ZKPassport SRS hash mismatch.');
      }
      await partial.rename(destination.path);
      _leasedPath = destination.path;
      return destination.path;
    } finally {
      await output?.close();
      client.close(force: true);
      await _deleteIfPresent(partial);
    }
  }

  @override
  Future<void> release(String path) async {
    await _deleteIfPresent(File(path));
    if (_leasedPath == path) {
      _leasedPath = null;
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A best-effort cleanup must not mask the proof or download error.
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
