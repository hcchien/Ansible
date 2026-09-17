import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

/// Resolves a DID to its registered handle (e.g. `alice.elix.cool`) via the
/// relay, so author bylines can show a friendly name instead of a raw DID.
/// Results have a short, origin-scoped cache; a feed
/// usually has few distinct authors, so this stays cheap.
class HandleResolver {
  HandleResolver({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _overrideBaseUri = baseUrl == null ? null : Uri.parse(baseUrl),
       _client = client ?? http.Client();

  final Uri? _overrideBaseUri;
  Uri get _baseUri =>
      _overrideBaseUri ?? Uri.parse(AppEnvironment.socialRelayBaseUrl);
  final http.Client _client;
  final Duration timeout;
  final Map<String, String?> _cache = {};
  final Map<String, DateTime> _cachedAt = {};
  final Map<String, String> _cachedOrigin = {};

  /// Shared instance so the cache is reused across screens.
  static final HandleResolver shared = HandleResolver();

  /// Synchronously returns a cached handle if known, else null. Useful for a
  /// first paint without flicker when the handle was already resolved.
  String? cached(String did) =>
      _cachedOrigin[did] == _baseUri.toString() ? _cache[did] : null;

  /// Pre-populates the cache with a known [did] → [handle] mapping, bypassing
  /// the network. Used by the screenshot harness (and tests) to render friendly
  /// bylines offline.
  void seed(String did, String handle) {
    _cache[did] = handle;
    _cachedAt[did] = DateTime.now();
    _cachedOrigin[did] = _baseUri.toString();
  }

  /// Returns the handle for [did], or null if unknown/unresolvable.
  Future<String?> handleFor(String did, {bool refresh = false}) async {
    final identity = did.trim();
    if (identity.isEmpty) return null;
    // Some imported/federated records already carry a handle in the author
    // field. Do not turn that friendly identifier into a failed DID lookup.
    if (!identity.startsWith('did:')) return identity.replaceFirst('@', '');
    if (!refresh &&
        _cachedOrigin[identity] == _baseUri.toString() &&
        DateTime.now().difference(_cachedAt[identity] ?? DateTime(1970)) <
            const Duration(minutes: 2)) {
      return _cache[identity];
    }
    final base = _baseUri;
    try {
      final response = await _client
          .get(_handleEndpoint(base, identity))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final handle = body is Map ? body['handle'] as String? : null;
        _cache[identity] = handle;
        _cachedAt[identity] = DateTime.now();
        _cachedOrigin[identity] = base.toString();
        return handle;
      }
      if (response.statusCode == 404) {
        _cache[identity] = null;
        _cachedAt[identity] = DateTime.now();
        _cachedOrigin[identity] = base.toString();
      }
      return null;
    } catch (_) {
      return null; // transient error — don't cache, allow a later retry
    }
  }

  Uri _handleEndpoint(Uri base, String did) => base.replace(
    pathSegments: [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
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
  const PublicAuthorProfile({
    this.displayName,
    this.handle,
    this.bio,
    this.avatarUrl,
    this.reputationTier,
    this.publicCredentials = const <PublicProfileCredential>[],
  });

  final String? displayName;
  final String? handle;
  final String? bio;
  final String? avatarUrl;

  /// Public AppView presentation metadata only. This may be shown as context,
  /// but must never be used as an authorization decision in the client.
  final String? reputationTier;
  final List<PublicProfileCredential> publicCredentials;

  String? get preferredLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final resolvedHandle = handle?.trim();
    if (resolvedHandle != null && resolvedHandle.isNotEmpty) {
      return resolvedHandle.startsWith('@')
          ? resolvedHandle
          : '@$resolvedHandle';
    }
    return null;
  }
}

class PublicProfileCredential {
  const PublicProfileCredential({
    required this.credentialType,
    required this.issuerDid,
    required this.badge,
    required this.value,
    this.validUntil,
  });

  final String credentialType;
  final String issuerDid;
  final String badge;
  final String value;
  final DateTime? validUntil;

  factory PublicProfileCredential.fromJson(Map<Object?, Object?> json) {
    return PublicProfileCredential(
      credentialType: json['credential_type'] as String? ?? '',
      issuerDid: json['issuer_did'] as String? ?? '',
      badge: json['badge'] as String? ?? '',
      value: json['value'] as String? ?? '',
      validUntil: DateTime.tryParse(json['valid_until'] as String? ?? ''),
    );
  }
}

/// Resolves the explicitly published display name from AppView and combines it
/// with the Relay's canonical DID handle. A handle carried in a profile op is
/// only a compatibility fallback because it can become stale after a rename.
class PublicProfileResolver {
  PublicProfileResolver({
    String? baseUrl,
    http.Client? client,
    HandleResolver? handleResolver,
    this.timeout = const Duration(seconds: 8),
  }) : _overrideBaseUri = baseUrl == null ? null : Uri.tryParse(baseUrl),
       _client = client ?? http.Client(),
       _handleResolver = handleResolver ?? HandleResolver.shared;

  final Uri? _overrideBaseUri;
  Uri? get _baseUri =>
      _overrideBaseUri ?? Uri.tryParse(AppEnvironment.socialRelayBaseUrl);
  final http.Client _client;
  final HandleResolver _handleResolver;
  final Duration timeout;
  final Map<String, PublicAuthorProfile?> _cache = {};
  final Map<String, DateTime> _cachedAt = {};
  final Map<String, String> _cachedOrigin = {};

  static final PublicProfileResolver shared = PublicProfileResolver();

  PublicAuthorProfile? cached(String did) => _cache[did];

  Future<PublicAuthorProfile?> profileFor(
    String did, {
    bool refresh = false,
  }) async {
    final identity = did.trim();
    if (identity.isEmpty) return null;
    if (!identity.startsWith('did:')) {
      return PublicAuthorProfile(handle: identity.replaceFirst('@', ''));
    }
    if (!refresh &&
        _cachedOrigin[identity] == _baseUri.toString() &&
        DateTime.now().difference(_cachedAt[identity] ?? DateTime(1970)) <
            const Duration(minutes: 2)) {
      return _cache[identity];
    }
    bool lookupFailed = false;

    // Resolve both public presentation sources concurrently so a slow Relay
    // cannot add another full timeout after the AppView lookup (or vice versa).
    final canonicalHandleFuture = _handleResolver.handleFor(
      identity,
      refresh: refresh,
    );
    PublicAuthorProfile? publishedProfile;
    final base = _baseUri;
    if (base != null && base.hasScheme && base.host.isNotEmpty) {
      try {
        final response = await _client
            .get(_profileEndpoint(base, identity))
            .timeout(timeout);
        if (response.statusCode == 200) {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map) {
            publishedProfile = PublicAuthorProfile(
              displayName:
                  body['display_name'] as String? ??
                  body['displayName'] as String?,
              handle: body['handle'] as String?,
              bio: body['bio'] as String?,
              avatarUrl:
                  body['avatar_url'] as String? ?? body['avatarUrl'] as String?,
              reputationTier:
                  body['reputation_tier'] as String? ??
                  body['reputationTier'] as String?,
              publicCredentials: (body['public_credentials'] is List)
                  ? (body['public_credentials'] as List)
                        .whereType<Map>()
                        .map(PublicProfileCredential.fromJson)
                        .where((credential) => credential.badge.isNotEmpty)
                        .toList(growable: false)
                  : const <PublicProfileCredential>[],
            );
          }
        } else if (response.statusCode != 404) {
          lookupFailed = true;
        }
      } catch (_) {
        lookupFailed = true;
        // Preserve the Relay fallback below when AppView is transiently down.
      }
    }

    if (lookupFailed && _cachedOrigin[identity] == base.toString()) {
      publishedProfile = _cache[identity];
    }
    final canonicalHandle = await canonicalHandleFuture;
    final profile = publishedProfile == null && canonicalHandle == null
        ? null
        : PublicAuthorProfile(
            displayName: publishedProfile?.displayName,
            handle: canonicalHandle ?? publishedProfile?.handle,
            bio: publishedProfile?.bio,
            avatarUrl: publishedProfile?.avatarUrl,
            reputationTier: publishedProfile?.reputationTier,
            publicCredentials:
                publishedProfile?.publicCredentials ??
                const <PublicProfileCredential>[],
          );
    _cache[identity] = profile;
    if (!lookupFailed) _cachedAt[identity] = DateTime.now();
    _cachedOrigin[identity] = base.toString();
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
