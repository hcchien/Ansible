import 'dart:convert';

import 'package:http/http.dart' as http;

import 'relay_identity_client.dart';

class RelayDiscoveryClient {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  RelayDiscoveryClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  Future<RelayDiscovery> fetchDiscovery() async {
    final response = await _client
        .get(_endpoint('/api/v1/discovery'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RelayDiscoveryException(
        response.statusCode,
        _decodeObjectOrEmpty(response.body),
      );
    }
    final decoded = _decodeJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected discovery JSON object');
    }
    return RelayDiscovery.fromJson(decoded);
  }

  /// The host's self-declared constitution compliance level from its own
  /// metadata (`GET /api/v1/forum-host`). Returns null when unreachable or
  /// undeclared — callers persist it on the saved host record (compliance
  /// review gap #2) and must treat it as display/ranking input only, never
  /// trust-bearing.
  Future<String?> fetchHostConstitutionCompliance() async {
    try {
      final response = await _client
          .get(_endpoint('/api/v1/forum-host'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = _decodeJson(response.body);
      if (decoded is! Map) return null;
      final level = decoded['constitution_compliance'];
      return level is String && level.isNotEmpty ? level : null;
    } catch (_) {
      return null;
    }
  }

  Object? _decodeJson(String responseBody) {
    if (responseBody.trim().isEmpty) return const {};
    return jsonDecode(responseBody);
  }

  Uri _endpoint(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '$basePath$path',
    );
  }

  void close() {
    _client.close();
  }
}

class RelayDiscoveryException implements Exception {
  final int statusCode;
  final Map<String, dynamic> body;

  const RelayDiscoveryException(this.statusCode, this.body);
}

Map<String, dynamic> _decodeObjectOrEmpty(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

class RelayDiscovery {
  final int version;
  final RelayDiscoveryRelay relay;
  final List<RelayAnnouncement> announcements;
  final List<DiscoveredForumHost> featuredForumHosts;
  final List<DiscoveredBoard> featuredBoards;
  final RelayDiscoveryCache? cache;

  const RelayDiscovery({
    required this.version,
    required this.relay,
    required this.announcements,
    required this.featuredForumHosts,
    required this.featuredBoards,
    this.cache,
  });

  factory RelayDiscovery.fromJson(Map<String, dynamic> json) {
    final cache = json['cache'];
    return RelayDiscovery(
      version: json['version'] as int,
      relay: RelayDiscoveryRelay.fromJson(
        Map<String, dynamic>.from(json['relay'] as Map),
      ),
      announcements: _list(
        json['announcements'],
      ).map(RelayAnnouncement.fromJson).toList(growable: false),
      featuredForumHosts: _list(
        json['featured_forum_hosts'],
      ).map(DiscoveredForumHost.fromJson).toList(growable: false),
      featuredBoards: _list(
        json['featured_boards'],
      ).map(DiscoveredBoard.fromJson).toList(growable: false),
      cache: cache is Map
          ? RelayDiscoveryCache.fromJson(Map<String, dynamic>.from(cache))
          : null,
    );
  }
}

class RelayDiscoveryRelay {
  final String serverKind;
  final String origin;
  final Map<String, Object?> capabilities;

  const RelayDiscoveryRelay({
    required this.serverKind,
    required this.origin,
    this.capabilities = const {},
  });

  factory RelayDiscoveryRelay.fromJson(Map<String, dynamic> json) {
    final capabilities = json['capabilities'];
    return RelayDiscoveryRelay(
      serverKind: json['server_kind'] as String,
      origin: json['origin'] as String,
      capabilities: capabilities is Map
          ? Map<String, Object?>.from(capabilities)
          : const {},
    );
  }
}

class RelayAnnouncement {
  final String announcementId;
  final String ownerKind;
  final String title;
  final String body;
  final String severity;
  final String? locale;

  const RelayAnnouncement({
    required this.announcementId,
    required this.ownerKind,
    required this.title,
    required this.body,
    required this.severity,
    this.locale,
  });

  factory RelayAnnouncement.fromJson(Map<String, dynamic> json) {
    return RelayAnnouncement(
      announcementId: json['announcement_id'] as String,
      ownerKind: json['owner_kind'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      severity: json['severity'] as String? ?? 'info',
      locale: json['locale'] as String?,
    );
  }
}

class DiscoveredForumHost {
  final String forumHostId;
  final String displayName;
  final String forumHostUrl;
  final String constitutionCompliance;

  const DiscoveredForumHost({
    required this.forumHostId,
    required this.displayName,
    required this.forumHostUrl,
    required this.constitutionCompliance,
  });

  factory DiscoveredForumHost.fromJson(Map<String, dynamic> json) {
    return DiscoveredForumHost(
      forumHostId: json['forum_host_id'] as String,
      displayName: json['display_name'] as String,
      forumHostUrl: json['forum_host_url'] as String,
      constitutionCompliance:
          json['constitution_compliance'] as String? ?? 'unknown',
    );
  }
}

class DiscoveredBoard {
  final String hostedBoardId;
  final String title;
  final String? description;
  final String forumHostUrl;
  final String canonicalBoardUri;
  final String constitutionCompliance;
  final List<String> tags;
  final String? language;

  const DiscoveredBoard({
    required this.hostedBoardId,
    required this.title,
    required this.forumHostUrl,
    required this.canonicalBoardUri,
    required this.constitutionCompliance,
    this.description,
    this.tags = const [],
    this.language,
  });

  factory DiscoveredBoard.fromJson(Map<String, dynamic> json) {
    return DiscoveredBoard(
      hostedBoardId:
          json['board_id']?.toString() ?? json['hosted_board_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      forumHostUrl: json['forum_host_url'] as String,
      canonicalBoardUri: json['canonical_board_uri'] as String,
      constitutionCompliance:
          json['constitution_compliance'] as String? ?? 'unknown',
      tags: _stringList(json['tags']),
      language: json['language'] as String?,
    );
  }
}

class RelayDiscoveryCache {
  final int? maxAgeSeconds;

  const RelayDiscoveryCache({this.maxAgeSeconds});

  factory RelayDiscoveryCache.fromJson(Map<String, dynamic> json) {
    return RelayDiscoveryCache(maxAgeSeconds: json['max_age_seconds'] as int?);
  }
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}
