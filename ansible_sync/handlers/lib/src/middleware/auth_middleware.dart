import 'package:shelf/shelf.dart';
import '../controllers/auth_controller.dart';
import '../utils/error_responses.dart';

/// Middleware that validates Bearer token authentication.
/// 
/// Extracts the Authorization header, validates the token,
/// and adds the userId to the request context.
/// 
/// Returns 401 if the token is missing or invalid.
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final authHeader = request.headers['authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return ErrorResponses.unauthorized();
      }

      final token = authHeader.substring('Bearer '.length).trim();
      final userId = AuthController.verifyToken(token);

      if (userId == null) {
        return ErrorResponses.unauthorized(
          message: 'Invalid or expired token',
        );
      }

      // Add userId to request context for downstream handlers
      final updatedRequest = request.change(context: {
        ...request.context,
        'userId': userId,
      });

      return innerHandler(updatedRequest);
    };
  };
}

/// Extension to easily access authenticated user ID from request context.
extension AuthContext on Request {
  String? get userId => context['userId'] as String?;
}
