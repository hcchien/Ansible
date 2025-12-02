import '../api/relay_api_client.dart';
import 'token_storage.dart';

class AuthService {
  final RelayApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthService({
    required RelayApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  Future<void> initialize() async {
    final token = await _tokenStorage.getToken();
    if (token != null) {
      _apiClient.setAccessToken(token);
    }
  }

  Future<void> login(String username, String password) async {
    try {
      final response = await _apiClient.login(username, password);
      final token = response['access_token'] as String;
      await _tokenStorage.saveToken(token);
      _apiClient.setAccessToken(token);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _tokenStorage.deleteToken();
    _apiClient.setAccessToken(null);
  }

  bool get isLoggedIn => _apiClient.hasToken;
}
