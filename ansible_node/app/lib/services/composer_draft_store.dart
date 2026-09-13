import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local drafts. Keys include identity, composer kind and destination;
/// these records are never part of sync or publication queues.
class ComposerDraftStore {
  ComposerDraftStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
  final FlutterSecureStorage _storage;
  static final shared = ComposerDraftStore();
  static final Map<String, Future<void>> _writes = {};

  static String key(String did, String kind, String target) =>
      'elix.composer.v1.${base64Url.encode(utf8.encode(jsonEncode([did, kind, target])))}';

  Future<Map<String, dynamic>?> read(String key) async {
    await _writes[key];
    final value = await _storage.read(key: key);
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> write(String key, Map<String, dynamic> value) =>
      _enqueue(key, () => _storage.write(key: key, value: jsonEncode(value)));
  Future<void> clear(String key) =>
      _enqueue(key, () => _storage.delete(key: key));

  Future<void> _enqueue(String key, Future<void> Function() action) {
    final future = (_writes[key] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => action());
    _writes[key] = future;
    void release() {
      if (identical(_writes[key], future)) _writes.remove(key);
    }

    future.then(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    return future;
  }
}
