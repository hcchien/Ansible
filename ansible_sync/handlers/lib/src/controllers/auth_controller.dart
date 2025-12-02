import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../utils/error_responses.dart';

/// Simple user model for POC
class User {
  final String userId;
  final String username;
  final String displayName;

  User({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'displayName': displayName,
    };
  }
}

class AuthController {
  // In-memory storage for POC
  static final Map<String, String> _tokens = {}; // token -> userId
  static final Map<String, User> _users = {}; // userId -> User

  Router get router {
    final router = Router();
    router.post('/login', _login);
    return router;
  }

  Future<Response> _login(Request request) async {
    try {
      final payload = await request.readAsString();
      final body = jsonDecode(payload);
      final username = body['username'] as String?;
      final password = body['password'] as String?;

      if (username == null || password == null) {
        return ErrorResponses.validationError(
          message: 'Missing username or password',
        );
      }

      // For POC: Accept any username/password and create/retrieve user
      // In real app: Verify credentials against database
      
      // Find or create user
      User user;
      final existingUser = _users.values
          .cast<User?>()
          .firstWhere((u) => u?.username == username, orElse: () => null);
      
      if (existingUser != null) {
        user = existingUser;
      } else {
        // Create new user
        final userId = 'user-${const Uuid().v4()}';
        user = User(
          userId: userId,
          username: username,
          displayName: _capitalize(username),
        );
        _users[userId] = user;
      }

      // Generate token
      final token = const Uuid().v4();
      _tokens[token] = user.userId;

      // POC2 format response
      return Response.ok(
        jsonEncode({
          'accessToken': token,
          'tokenType': 'Bearer',
          'expiresIn': 3600,
          'user': user.toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return ErrorResponses.internalError(message: 'Login failed: $e');
    }
  }

  // Helper to verify token and return userId
  static String? verifyToken(String token) {
    return _tokens[token];
  }

  // Helper to get user by ID
  static User? getUserById(String userId) {
    return _users[userId];
  }

  // Simple capitalize helper
  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
