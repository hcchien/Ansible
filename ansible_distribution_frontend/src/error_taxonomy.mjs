import { RelayApiError } from './relay_api_client.mjs';

export const ERROR_TYPES = Object.freeze({
  unauthenticated: 'unauthenticated',
  missingScope: 'missing_scope',
  rateLimited: 'rate_limited',
  challengeExpired: 'challenge_expired',
  sessionExpired: 'session_expired',
  networkUnavailable: 'network_unavailable',
  invalidRequest: 'invalid_request',
  notFound: 'not_found',
  relayError: 'relay_error',
  unknown: 'unknown_error',
});

export function normalizeFrontendError(error) {
  if (isFrontendSemanticError(error)) {
    return error;
  }

  if (error instanceof RelayApiError) {
    return relayError(error);
  }

  if (error instanceof TypeError) {
    return normalizedError(ERROR_TYPES.networkUnavailable, error.message, {
      retryable: true,
    });
  }

  return normalizedError(ERROR_TYPES.unknown, error?.message ?? 'unknown_error', {
    retryable: true,
  });
}

export function scopeError(requiredScope) {
  return normalizedError(
    ERROR_TYPES.missingScope,
    `Missing required scope: ${requiredScope}`,
    {
      retryable: false,
      code: 'missing_scope',
      detail: { requiredScope },
    },
  );
}

export function notFoundError(message = 'not_found', detail) {
  return normalizedError(ERROR_TYPES.notFound, message, {
    retryable: false,
    code: 'not_found',
    detail,
  });
}

function relayError(error) {
  const type = errorTypeForRelayFailure(error);

  return normalizedError(type, error.message, {
    retryable: retryableForType(type),
    status: error.status,
    code: error.code,
    detail: error.detail,
  });
}

function errorTypeForRelayFailure(error) {
  if (error.status === 401) {
    if (error.code === 'session_expired') {
      return ERROR_TYPES.sessionExpired;
    }

    return ERROR_TYPES.unauthenticated;
  }

  if (error.status === 403) {
    return ERROR_TYPES.missingScope;
  }

  if (error.status === 404) {
    return ERROR_TYPES.notFound;
  }

  if (error.status === 429 || error.code === 'rate_limited') {
    return ERROR_TYPES.rateLimited;
  }

  if (
    ['expired', 'challenge_expired', 'challenge_not_found', 'expired_grant'].includes(
      error.code,
    )
  ) {
    return ERROR_TYPES.challengeExpired;
  }

  if (
    [
      'invalid_scopes',
      'invalid_request',
      'invalid_thread',
      'invalid_board',
      'missing_required_fields',
    ].includes(error.code)
  ) {
    return ERROR_TYPES.invalidRequest;
  }

  return ERROR_TYPES.relayError;
}

function retryableForType(type) {
  return [
    ERROR_TYPES.unauthenticated,
    ERROR_TYPES.rateLimited,
    ERROR_TYPES.challengeExpired,
    ERROR_TYPES.sessionExpired,
    ERROR_TYPES.networkUnavailable,
    ERROR_TYPES.relayError,
    ERROR_TYPES.unknown,
  ].includes(type);
}

function normalizedError(
  type,
  message,
  { retryable, status, code, detail } = {},
) {
  return {
    type,
    message,
    retryable,
    status,
    code,
    detail,
  };
}

function isFrontendSemanticError(error) {
  return Boolean(error?.type && Object.values(ERROR_TYPES).includes(error.type));
}
