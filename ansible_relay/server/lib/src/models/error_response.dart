import 'dart:convert';

import 'package:shelf/shelf.dart';

class ErrorResponse {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int statusCode;

  ErrorResponse({
    required this.code,
    required this.message,
    this.details,
    required this.statusCode,
  });

  Map<String, dynamic> toJson() {
    return {
      'error': {
        'code': code,
        'message': message,
        if (details != null) 'details': details,
      }
    };
  }

  Response toShelfResponse() {
    return Response(
      statusCode,
      body: jsonEncode(toJson()),
      headers: {
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  static ErrorResponse unauthorized([String? message]) => ErrorResponse(
        code: 'UNAUTHORIZED',
        message: message ?? 'Unauthorized',
        statusCode: 401,
      );

  static ErrorResponse forbidden([String? message]) => ErrorResponse(
        code: 'FORBIDDEN',
        message: message ?? 'Forbidden',
        statusCode: 403,
      );

  static ErrorResponse notFound(String code, String message) => ErrorResponse(
        code: code,
        message: message,
        statusCode: 404,
      );

  static ErrorResponse validation(String message,
          {Map<String, dynamic>? details}) =>
      ErrorResponse(
        code: 'VALIDATION_ERROR',
        message: message,
        details: details,
        statusCode: 400,
      );

  static ErrorResponse internal([String? message]) => ErrorResponse(
        code: 'INTERNAL_ERROR',
        message: message ?? 'Internal server error',
        statusCode: 500,
      );
}
