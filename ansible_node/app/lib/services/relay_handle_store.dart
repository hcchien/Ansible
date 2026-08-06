import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the human-readable handle chosen for a particular Relay space.
///
/// A handle is local to a Relay namespace. The DID and its signing key remain
/// the durable identity and are deliberately not changed when this value is
/// updated.
abstract class RelayHandleStore {
  Future<String?> load(String relayUrl);
  Future<void> save(String relayUrl, String handle);
  Future<void> delete(String relayUrl);
}

class SecureRelayHandleStore implements RelayHandleStore {
  const SecureRelayHandleStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> load(String relayUrl) => _storage.read(key: _key(relayUrl));

  @override
  Future<void> save(String relayUrl, String handle) {
    return _storage.write(
      key: _key(relayUrl),
      value: handle.trim().toLowerCase(),
    );
  }

  @override
  Future<void> delete(String relayUrl) => _storage.delete(key: _key(relayUrl));

  String _key(String relayUrl) {
    final uri = Uri.parse(relayUrl);
    final origin = uri.hasPort
        ? '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}'
        : '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}';
    final encoded = base64UrlEncode(utf8.encode(origin)).replaceAll('=', '');
    return 'ansible_relay_handle_$encoded';
  }
}
