import 'dart:convert';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

/// Compatibility client for the legacy Sync Settings screen.
///
/// The old password-auth Dart relay has been removed. V1.1 uses DID anchoring
/// plus signed Ops, so this class only keeps the screen compilable while the
/// full Phase 2 Ops dispatcher replaces board-level pull sync.
class RelayApiClient {
  final String baseUrl;
  final http.Client _client;
  String? _accessToken;

  RelayApiClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Relay authentication failed: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, String> get authHeaders {
    final token = _accessToken;
    return {
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }
}

class RemoteSyncService {
  RemoteSyncService({
    required DriftRemoteNodeRepository remoteNodeRepo,
    required DriftBoardSyncConfigRepository boardSyncConfigRepo,
    required DriftBoardRepository boardRepo,
    required DriftThreadRepository threadRepo,
    required DriftPostRepository postRepo,
  });

  Future<SyncResult> syncFromNode(
    RelayApiClient client,
    RemoteNode node,
  ) async {
    return SyncResult.failure(
      errorMessage:
          'Legacy board sync is disabled. V1.1 sync will use signed Ops in Phase 2.',
    );
  }
}
