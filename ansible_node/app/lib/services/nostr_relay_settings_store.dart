import 'dart:convert';

import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class NostrRelaySettingsStore {
  Future<List<NostrRelayPreference>> list();
  Future<void> save(List<NostrRelayPreference> relays);
}

class SecureStorageNostrRelaySettingsStore implements NostrRelaySettingsStore {
  static const storageKey = 'ansible_nostr_relays';

  final FlutterSecureStorage _secureStorage;

  const SecureStorageNostrRelaySettingsStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<List<NostrRelayPreference>> list() async {
    final raw = await _secureStorage.read(key: storageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return const [];

    final relays = <NostrRelayPreference>[];
    for (final entry in decoded) {
      if (entry is! Map<dynamic, dynamic>) continue;
      final url = entry['url'];
      final read = entry['read'];
      final write = entry['write'];
      if (url is! String) continue;
      final preference = _preferenceOrNull(
        url: url,
        read: read == true,
        write: write == true,
      );
      if (preference != null) relays.add(preference);
    }
    return _normalize(relays);
  }

  @override
  Future<void> save(List<NostrRelayPreference> relays) async {
    final normalized = _normalize(relays);
    await _secureStorage.write(
      key: storageKey,
      value: jsonEncode([
        for (final relay in normalized)
          {'url': relay.url, 'read': relay.read, 'write': relay.write},
      ]),
    );
  }

  static List<NostrRelayPreference> _normalize(
    List<NostrRelayPreference> relays,
  ) {
    final byUrl = <String, ({bool read, bool write})>{};
    for (final relay in relays) {
      final url = relay.url.trim();
      if (url.isEmpty || !_isRelayUrl(url)) continue;
      final existing = byUrl[url] ?? (read: false, write: false);
      byUrl[url] = (
        read: existing.read || relay.read,
        write: existing.write || relay.write,
      );
    }

    return [
      for (final entry in byUrl.entries)
        if (entry.value.read || entry.value.write)
          NostrRelayPreference(
            url: entry.key,
            read: entry.value.read,
            write: entry.value.write,
          ),
    ];
  }

  static NostrRelayPreference? _preferenceOrNull({
    required String url,
    required bool read,
    required bool write,
  }) {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty || !_isRelayUrl(normalizedUrl)) return null;
    if (!read && !write) return null;
    return NostrRelayPreference(url: normalizedUrl, read: read, write: write);
  }

  static bool _isRelayUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'wss' || uri.scheme == 'ws') &&
        uri.host.isNotEmpty;
  }
}
