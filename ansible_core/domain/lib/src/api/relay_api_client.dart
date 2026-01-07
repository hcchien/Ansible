import 'dart:convert';
import 'package:http/http.dart' as http;

class RelayApiClient {
  final String baseUrl;
  final http.Client _client;
  String? _accessToken;

  RelayApiClient({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  bool get hasToken => _accessToken != null;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Login failed: ${response.statusCode} - ${response.body}');
    }
  }

  Future<http.Response> get(String endpoint) async {
    return _client.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: _authHeaders(),
    );
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    return _client.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: _authHeaders(),
      body: jsonEncode(body),
    );
  }

  Future<Map<String, dynamic>> getDelta({int? cursor, int limit = 100}) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
    };
    if (cursor != null) {
      queryParams['cursor'] = cursor.toString();
    }

    final uri = Uri.parse('$baseUrl/api/v1/sync/delta')
        .replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _authHeaders());

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch delta: ${response.statusCode} - ${response.body}');
  }

  Future<Map<String, dynamic>> getBoards() async {
    final response = await get('/api/v1/boards');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch boards: ${response.statusCode} - ${response.body}');
  }

  Map<String, String> _authHeaders() {
    final headers = {'Content-Type': 'application/json'};
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }
}
