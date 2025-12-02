import 'package:shelf/shelf.dart';
import 'api_error.dart';
import 'error_code.dart';

/// Factory functions for creating standardized error responses.
class ErrorResponses {
  /// 401 Unauthorized - Missing or invalid authorization token
  static Response unauthorized({String? message}) {
    return ApiError(
      code: ErrorCode.unauthorized,
      message: message ?? 'Missing or invalid authorization token',
    ).toResponse(401);
  }

  /// 403 Forbidden - User lacks permission for this operation
  static Response forbidden({String? message}) {
    return ApiError(
      code: ErrorCode.forbidden,
      message: message ?? 'You do not have permission to perform this action',
    ).toResponse(403);
  }

  /// 404 Not Found - Generic not found error
  static Response notFound({
    required ErrorCode code,
    required String message,
    Map<String, dynamic>? details,
  }) {
    return ApiError(
      code: code,
      message: message,
      details: details,
    ).toResponse(404);
  }

  /// 400 Validation Error - Request validation failed
  static Response validationError({
    required String message,
    Map<String, dynamic>? details,
  }) {
    return ApiError(
      code: ErrorCode.validationError,
      message: message,
      details: details,
    ).toResponse(400);
  }

  /// 409 Conflict - Resource conflict (e.g., duplicate ID)
  static Response conflict({
    required String message,
    Map<String, dynamic>? details,
  }) {
    return ApiError(
      code: ErrorCode.conflict,
      message: message,
      details: details,
    ).toResponse(409);
  }

  /// 500 Internal Server Error
  static Response internalError({String? message}) {
    return ApiError(
      code: ErrorCode.internalError,
      message: message ?? 'An internal error occurred',
    ).toResponse(500);
  }
}
