import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PassportLocalIdService {
  static const _storageKey = 'trisaura.wallet.passport_local_secret.v1';

  final FlutterSecureStorage _secureStorage;
  final String? _fixedSecret;

  const PassportLocalIdService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
      _fixedSecret = null;

  const PassportLocalIdService.fixedSecret(String secret)
    : _secureStorage = const FlutterSecureStorage(),
      _fixedSecret = secret;

  String derive({required String nationality, required String documentNumber}) {
    final secret = _fixedSecret;
    if (secret == null) {
      throw StateError('Use deriveWithStoredSecret for production derivation.');
    }
    return _deriveWithSecret(
      secret: secret,
      nationality: nationality,
      documentNumber: documentNumber,
    );
  }

  Future<String> deriveWithStoredSecret({
    required String nationality,
    required String documentNumber,
  }) async {
    final secret = _fixedSecret ?? await _loadOrCreateSecret();
    return _deriveWithSecret(
      secret: secret,
      nationality: nationality,
      documentNumber: documentNumber,
    );
  }

  Future<String> _loadOrCreateSecret() async {
    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final secret = base64UrlEncode(bytes);
    await _secureStorage.write(key: _storageKey, value: secret);
    return secret;
  }

  String _deriveWithSecret({
    required String secret,
    required String nationality,
    required String documentNumber,
  }) {
    final normalizedNationality = nationality.trim().toUpperCase();
    final payload = 'passport:v1|$normalizedNationality|$documentNumber';
    final mac = Hmac(sha256, utf8.encode(secret));
    final digest = mac.convert(utf8.encode(payload));
    return 'passport-local-v1-$digest';
  }
}
