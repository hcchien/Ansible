import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/error_response.dart';

class AuthHandler {
  AuthHandler({UserRepository? userRepository})
    : _userRepository = userRepository;

  final UserRepository? _userRepository;

  Router get router {
    final router = Router();

    router.post('/login', _login);

    return router;
  }

  Future<Response> _login(Request request) async {
    final bodyString = await request.readAsString();
    if (bodyString.isEmpty) {
      return ErrorResponse.validation('Empty body').toShelfResponse();
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyString) as Map<String, dynamic>;
    } catch (_) {
      return ErrorResponse.validation('Invalid JSON').toShelfResponse();
    }

    final username = body['username'] as String?;
    final password = body['password'] as String?;

    if (username == null || password == null) {
      return ErrorResponse.validation(
        'username and password are required',
      ).toShelfResponse();
    }

    final user = await _authenticate(username, password);
    if (user == null) {
      return ErrorResponse.unauthorized(
        'Invalid credentials',
      ).toShelfResponse();
    }

    final token = 'user:${user.userId}';

    final responseBody = {
      'accessToken': token,
      'tokenType': 'Bearer',
      'expiresIn': 3600,
      'user': {
        'userId': user.userId,
        'username': user.username,
        'displayName': user.displayName ?? user.username,
      },
    };

    return Response.ok(
      jsonEncode(responseBody),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<User?> _authenticate(String username, String password) async {
    if (_userRepository == null) {
      // POC fallback: accept any credentials.
      return User(
        userId: 'user-123',
        username: username,
        passwordHash: password,
        displayName: username,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    final user = await _userRepository.getByUsername(username);
    if (user == null) {
      return null;
    }

    // For now we treat passwordHash as plaintext. Replace with bcrypt/argon2 verification later.
    if (user.passwordHash != password) {
      return null;
    }

    return user;
  }
}
