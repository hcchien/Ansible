class FollowQrLink {
  const FollowQrLink(this.did);

  final String did;

  static final _did = RegExp(
    r'^did:(?:elix:[a-z2-7]{26}|plc:[a-z2-7]{10,}|key:z[1-9A-HJ-NP-Za-km-z]{40,120}|web:[A-Za-z0-9._%:-]+)$',
  );

  String encode() => Uri(
    scheme: 'elix',
    host: 'follow',
    queryParameters: {'did': did},
  ).toString();

  static FollowQrLink parse(String raw) {
    final uri = Uri.tryParse(raw);
    final did = uri?.queryParameters['did'];
    if (uri?.scheme != 'elix' ||
        uri?.host != 'follow' ||
        did == null ||
        !_did.hasMatch(did)) {
      throw const FormatException('invalid_follow_qr');
    }
    return FollowQrLink(did);
  }
}
