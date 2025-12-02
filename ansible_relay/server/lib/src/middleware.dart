import 'package:shelf/shelf.dart';

import 'models/error_response.dart';

Middleware jsonContentTypeMiddleware() {
  return (innerHandler) {
    return (request) async {
      final response = await innerHandler(request);
      if (response.headers['content-type'] == null) {
        return response.change(
          headers: {
            ...response.headers,
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      return response;
    };
  };
}

Middleware corsMiddleware() {
  return (innerHandler) {
    return (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: {
        ...response.headers,
        ..._corsHeaders,
      });
    };
  };
}

const Map<String, String> _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers':
      'Origin, Content-Type, Authorization, X-Sync-Version',
};

Middleware authMiddleware() {
  return (innerHandler) {
    return (request) async {
      if (_isPublicPath(request.url.path)) {
        return innerHandler(request);
      }

      final authHeader = request.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return ErrorResponse.unauthorized('Missing Authorization header').toShelfResponse();
      }

      final token = authHeader.substring('Bearer '.length).trim();
      final userId = _extractUserId(token);
      if (userId == null) {
        return ErrorResponse.unauthorized('Invalid access token').toShelfResponse();
      }

      final updatedRequest = request.change(context: {
        ...request.context,
        'userId': userId,
      });

      return innerHandler(updatedRequest);
    };
  };
}

bool _isPublicPath(String path) {
  return path == 'health' || path.startsWith('api/v1/auth/login');
}

String? _extractUserId(String token) {
  if (token.startsWith('user:')) {
    final candidate = token.substring('user:'.length);
    return candidate.isNotEmpty ? candidate : null;
  }
  return token.isNotEmpty ? token : null;
}
