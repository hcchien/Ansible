import 'package:ansible_node/services/follow_qr_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips a follow QR DID without extra data', () {
    const did = 'did:elix:abcdefghijklmnopqrstuvwxyz';
    final encoded = const FollowQrLink(did).encode();
    expect(FollowQrLink.parse(encoded).did, did);
    expect(encoded, isNot(contains('passport')));
  });

  test('rejects non-follow and malformed QR payloads', () {
    expect(
      () => FollowQrLink.parse('https://example.com'),
      throwsFormatException,
    );
    expect(
      () => FollowQrLink.parse('elix://follow?did=not-a-did'),
      throwsFormatException,
    );
  });
}
