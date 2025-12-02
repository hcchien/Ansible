/// Standardized error codes for the POC2 API specification.
enum ErrorCode {
  unauthorized('UNAUTHORIZED'),
  forbidden('FORBIDDEN'),
  boardNotFound('BOARD_NOT_FOUND'),
  threadNotFound('THREAD_NOT_FOUND'),
  postNotFound('POST_NOT_FOUND'),
  validationError('VALIDATION_ERROR'),
  conflict('CONFLICT'),
  internalError('INTERNAL_ERROR');

  const ErrorCode(this.code);
  final String code;
}
