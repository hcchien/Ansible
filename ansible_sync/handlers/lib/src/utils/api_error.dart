import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'error_code.dart';

/// Represents a standardized API error following POC2 specification.
class ApiError {
  final ErrorCode code;
  final String message;
  final Map<String, dynamic>? details;

  ApiError({
    required this.code,
    required this.message,
    this.details,
  });

  /// Converts the error to JSON format matching POC2 spec:
  /// {
  ///   "error": {
  ///     "code": "BOARD_NOT_FOUND",
  ///     "message": "Board not found",
  ///     "details": { ... }  // optional
  ///   }
  /// }
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> error = {
      'code': code.code,
      'message': message,
    };
    if (details != null) {
      error['details'] = details!;
    }
    return {'error': error};
  }

  /// Creates a Shelf Response with the appropriate status code and error body.
  Response toResponse(int statusCode) {
    return Response(
      statusCode,
      body: jsonEncode(toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
