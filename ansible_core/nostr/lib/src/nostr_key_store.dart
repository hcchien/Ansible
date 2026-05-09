abstract class NostrKeyStore {
  Future<NostrKeyMaterial?> read();
  Future<void> save(NostrKeyMaterial key);
  Future<void> clear();
}

class NostrKeyMaterial {
  final String privateKeyHex;
  final String publicKeyHex;

  NostrKeyMaterial({
    required String privateKeyHex,
    required String publicKeyHex,
  }) : privateKeyHex = _normalizePrivateKey(privateKeyHex),
       publicKeyHex = _normalizePublicKey(publicKeyHex);

  static String _normalizePrivateKey(String value) {
    return _normalizeHex(value, label: 'Nostr private key');
  }

  static String _normalizePublicKey(String value) {
    return _normalizeHex(value, label: 'Nostr public key');
  }

  static String _normalizeHex(String value, {required String label}) {
    final lower = value.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(lower) ||
        lower.startsWith('deadbeef') ||
        lower.startsWith('dev') ||
        lower.startsWith('stub') ||
        lower.contains('stub')) {
      throw ArgumentError('$label must be a real 32-byte hex value');
    }
    return lower;
  }

  @override
  bool operator ==(Object other) {
    return other is NostrKeyMaterial &&
        other.privateKeyHex == privateKeyHex &&
        other.publicKeyHex == publicKeyHex;
  }

  @override
  int get hashCode => Object.hash(privateKeyHex, publicKeyHex);
}

class InMemoryNostrKeyStore implements NostrKeyStore {
  NostrKeyMaterial? _key;

  @override
  Future<NostrKeyMaterial?> read() async => _key;

  @override
  Future<void> save(NostrKeyMaterial key) async {
    _key = key;
  }

  @override
  Future<void> clear() async {
    _key = null;
  }
}
