import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

/// Resolves a DID to its registered handle (e.g. `alice.elix.cool`) via the
/// relay, so author bylines can show a friendly name instead of a raw DID.
/// Results — including negatives — are cached for the process lifetime; a feed
/// usually has few distinct authors, so this stays cheap.
class HandleResolver {
  HandleResolver({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _baseUri = Uri.parse(baseUrl ?? AppEnvironment.atProtoBaseUrl),
       _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;
  final Map<String, String?> _cache = {};

  /// Shared instance so the cache is reused across screens.
  static final HandleResolver shared = HandleResolver();

  /// Synchronously returns a cached handle if known, else null. Useful for a
  /// first paint without flicker when the handle was already resolved.
  String? cached(String did) => _cache[did];

  /// Pre-populates the cache with a known [did] → [handle] mapping, bypassing
  /// the network. Used by the screenshot harness (and tests) to render friendly
  /// bylines offline.
  void seed(String did, String handle) => _cache[did] = handle;

  /// Returns the handle for [did], or null if unknown/unresolvable.
  Future<String?> handleFor(String did) async {
    if (did.isEmpty) return null;
    if (_cache.containsKey(did)) return _cache[did];
    try {
      final response = await _client
          .get(_endpoint('/api/v1/identity/handle/${Uri.encodeComponent(did)}'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final handle = body is Map ? body['handle'] as String? : null;
        _cache[did] = handle; // cache success (incl. null body)
        return handle;
      }
      if (response.statusCode == 404) {
        _cache[did] = null; // cache the negative
      }
      return null;
    } catch (_) {
      return null; // transient error — don't cache, allow a later retry
    }
  }

  Uri _endpoint(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return Uri(
      scheme: _baseUri.scheme,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: '$basePath$path',
    );
  }
}

/// A short, human-readable form of a DID for fallback display when the handle
/// can't be resolved, e.g. `did:plc:fpgq…xozmu`.
String shortenDid(String did) {
  if (did.length <= 18) return did;
  return '${did.substring(0, 12)}…${did.substring(did.length - 5)}';
}
