import 'package:ansible_domain/ansible_domain.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FlutterSecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'auth_token';

  FlutterSecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  @override
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  @override
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }
}
