import assert from 'node:assert/strict';

import {
  ERROR_TYPES,
  normalizeFrontendError,
  scopeError,
} from '../src/error_taxonomy.mjs';
import { RelayApiError } from '../src/relay_api_client.mjs';

const cases = [
  [
    'invalid web session',
    new RelayApiError('invalid_web_session', {
      status: 401,
      code: 'invalid_web_session',
    }),
    {
      type: ERROR_TYPES.unauthenticated,
      message: 'invalid_web_session',
      retryable: true,
      status: 401,
      code: 'invalid_web_session',
      detail: undefined,
    },
  ],
  [
    'missing scope',
    new RelayApiError('missing_scope', { status: 403, code: 'missing_scope' }),
    {
      type: ERROR_TYPES.missingScope,
      message: 'missing_scope',
      retryable: false,
      status: 403,
      code: 'missing_scope',
      detail: undefined,
    },
  ],
  [
    'posting requires tier',
    new RelayApiError('posting_requires_tier', {
      status: 403,
      code: 'posting_requires_tier',
      body: {
        error: 'posting_requires_tier',
        required_tier: 'verified_human',
        current_tier: 'basic',
      },
    }),
    {
      type: ERROR_TYPES.postingRequiresTier,
      message: 'posting_requires_tier',
      retryable: false,
      status: 403,
      code: 'posting_requires_tier',
      detail: { requiredTier: 'verified_human', currentTier: 'basic' },
    },
  ],
  [
    'rate limited',
    new RelayApiError('rate_limited', {
      status: 429,
      code: 'rate_limited',
      detail: { retry_after_seconds: 30 },
    }),
    {
      type: ERROR_TYPES.rateLimited,
      message: 'rate_limited',
      retryable: true,
      status: 429,
      code: 'rate_limited',
      detail: { retry_after_seconds: 30 },
    },
  ],
  [
    'challenge expired',
    new RelayApiError('expired', { status: 422, code: 'expired' }),
    {
      type: ERROR_TYPES.challengeExpired,
      message: 'expired',
      retryable: true,
      status: 422,
      code: 'expired',
      detail: undefined,
    },
  ],
  [
    'invalid request',
    new RelayApiError('invalid_scopes', { status: 422, code: 'invalid_scopes' }),
    {
      type: ERROR_TYPES.invalidRequest,
      message: 'invalid_scopes',
      retryable: false,
      status: 422,
      code: 'invalid_scopes',
      detail: undefined,
    },
  ],
  [
    'network unavailable',
    new TypeError('Failed to fetch'),
    {
      type: ERROR_TYPES.networkUnavailable,
      message: 'Failed to fetch',
      retryable: true,
      status: undefined,
      code: undefined,
      detail: undefined,
    },
  ],
];

for (const [name, input, expected] of cases) {
  assert.deepEqual(normalizeFrontendError(input), expected);
  console.log(`ok - normalizes ${name}`);
}

assert.deepEqual(scopeError('forum:post'), {
  type: ERROR_TYPES.missingScope,
  message: 'Missing required scope: forum:post',
  retryable: false,
  status: undefined,
  code: 'missing_scope',
  detail: { requiredScope: 'forum:post' },
});
console.log('ok - creates local scope errors');
