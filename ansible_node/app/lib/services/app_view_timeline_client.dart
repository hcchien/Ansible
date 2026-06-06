import 'dart:convert';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:http/http.dart' as http;

/// HTTP client for the AppView timeline API. Its [fetch] matches the
/// `AppViewTimelineFetcher` typedef, so it plugs straight into
/// `AppViewTimelineSource`. (Client-side Ed25519 re-verification is a follow-up:
/// it requires the AppView to return the original signed payload + signature,
/// which feed_items does not yet store; today the app trusts the first-party
/// AppView's ingest-time verification, the same trust as the relay delta.)
class AppViewTimelineClient {
  final String baseUrl;
  final http.Client _client;

  AppViewTimelineClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  Future<AppViewTimelinePage> fetch({
    required List<String> dids,
    int? cursor,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/timeline',
    );
    final response = await _client.post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'dids': dids,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      }),
    );

    return _parse('timeline', response);
  }

  /// Fetches the reader's server-materialized home timeline (fan-out-on-write).
  /// Matches the `AppViewHomeFetcher` typedef. The app sends only its own DID;
  /// the AppView assembles the page from the reader's pre-built home timeline.
  Future<AppViewTimelinePage> fetchHome({
    required String readerDid,
    int? cursor,
    int limit = 50,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/home').replace(
      queryParameters: {
        'reader': readerDid,
        if (cursor != null) 'cursor': '$cursor',
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri);
    return _parse('home', response);
  }

  AppViewTimelinePage _parse(String label, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AppView $label failed: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) {
          final m = Map<String, dynamic>.from(raw);
          return AppViewTimelineItem(
            entityType: m['entity_type'] as String? ?? '',
            entityId: m['entity_id'] as String? ?? '',
            authorDid: m['author_did'] as String? ?? '',
            boardId: m['board_id'] as String?,
            threadId: m['thread_id'] as String?,
            visibility: m['visibility'] as String?,
            createdAt: m['created_at'] is String
                ? DateTime.tryParse(m['created_at'] as String)
                : null,
            payload: Map<String, dynamic>.from(
              (m['payload'] as Map?) ?? const {},
            ),
          );
        })
        .toList();

    return AppViewTimelinePage(
      items: items,
      nextCursor: body['next_cursor'] as int?,
      hasMore: body['has_more'] as bool? ?? false,
    );
  }
}
