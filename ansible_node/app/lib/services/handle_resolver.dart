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
    final identity = did.trim();
    if (identity.isEmpty) return null;
    // Some imported/federated records already carry a handle in the author
    // field. Do not turn that friendly identifier into a failed DID lookup.
    if (!identity.startsWith('did:')) return identity.replaceFirst('@', '');
    if (_cache.containsKey(identity)) return _cache[identity];
    try {
      final response = await _client
          .get(_handleEndpoint(identity))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final handle = body is Map ? body['handle'] as String? : null;
        _cache[identity] = handle; // cache success (incl. null body)
        return handle;
      }
      if (response.statusCode == 404) {
        _cache[identity] = null; // cache the negative
      }
      return null;
    } catch (_) {
      return null; // transient error — don't cache, allow a later retry
    }
  }

  Uri _handleEndpoint(String did) => _baseUri.replace(
    pathSegments: [
      ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      'api',
      'v1',
      'identity',
      'handle',
      did,
    ],
    query: null,
    fragment: null,
  );
}

/// Public, presentation-only profile data projected by the AppView.  It is
/// intentionally separate from a DID's verification key and must not be used
/// for authorization, signing, or follow-target identity.
class PublicAuthorProfile {
  const PublicAuthorProfile({this.displayName, this.handle});

  final String? displayName;
  final String? handle;

  String? get preferredLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final resolvedHandle = handle?.trim();
    if (resolvedHandle != null && resolvedHandle.isNotEmpty) {
      return resolvedHandle;
    }
    return null;
  }
}

/// Resolves the explicitly published public profile from AppView, with the
/// relay handle lookup retained as a compatibility fallback while an AppView is
/// unavailable or an older account has not yet published a profile op.
class PublicProfileResolver {
  PublicProfileResolver({
    String? baseUrl,
    http.Client? client,
    HandleResolver? handleResolver,
    this.timeout = const Duration(seconds: 8),
  }) : _baseUri = Uri.tryParse(baseUrl ?? AppEnvironment.appViewBaseUrl),
       _client = client ?? http.Client(),
       _handleResolver = handleResolver ?? HandleResolver.shared;

  final Uri? _baseUri;
  final http.Client _client;
  final HandleResolver _handleResolver;
  final Duration timeout;
  final Map<String, PublicAuthorProfile?> _cache = {};

  static final PublicProfileResolver shared = PublicProfileResolver();

  PublicAuthorProfile? cached(String did) => _cache[did];

  Future<PublicAuthorProfile?> profileFor(String did) async {
    final identity = did.trim();
    if (identity.isEmpty) return null;
    if (!identity.startsWith('did:')) {
      return PublicAuthorProfile(handle: identity.replaceFirst('@', ''));
    }
    if (_cache.containsKey(identity)) return _cache[identity];

    final base = _baseUri;
    if (base != null && base.hasScheme && base.host.isNotEmpty) {
      try {
        final response = await _client
            .get(_profileEndpoint(base, identity))
            .timeout(timeout);
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body is Map) {
            final profile = PublicAuthorProfile(
              displayName:
                  body['display_name'] as String? ??
                  body['displayName'] as String?,
              handle: body['handle'] as String?,
            );
            _cache[identity] = profile;
            return profile;
          }
        }
        if (response.statusCode == 404) _cache[identity] = null;
      } catch (_) {
        // Transient AppView failure: preserve the older relay fallback below.
      }
    }

    final handle = await _handleResolver.handleFor(identity);
    final profile = handle == null ? null : PublicAuthorProfile(handle: handle);
    _cache[identity] = profile;
    return profile;
  }

  Uri _profileEndpoint(Uri base, String did) => base.replace(
    pathSegments: [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      'api',
      'v1',
      'profiles',
      did,
    ],
    query: null,
    fragment: null,
  );
}

/// A short, human-readable form of a DID for fallback display when the handle
/// can't be resolved, e.g. `did:plc:fpgq…xozmu`.
String shortenDid(String did) {
  if (did.length <= 18) return did;
  return '${did.substring(0, 12)}…${did.substring(did.length - 5)}';
}
