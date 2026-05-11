import assert from 'node:assert/strict';

import {
  createHostedWebThread,
  createForumDataAdapter,
  createPageController,
  createRelayApiClient,
  createSessionLifecycle,
  createWebSessionChallenge,
  ERROR_TYPES,
  fetchForumHostInfo,
  fetchHostedBoards,
  listWebSessions,
  normalizeFrontendError,
  PAGE_IDS,
  parseRoute,
  revokeWebSession,
} from '../src/api.mjs';

assert.equal(typeof createRelayApiClient, 'function');
assert.equal(typeof createWebSessionChallenge, 'function');
assert.equal(typeof listWebSessions, 'function');
assert.equal(typeof revokeWebSession, 'function');
assert.equal(typeof fetchForumHostInfo, 'function');
assert.equal(typeof fetchHostedBoards, 'function');
assert.equal(typeof createHostedWebThread, 'function');
assert.equal(typeof createSessionLifecycle, 'function');
assert.equal(typeof createForumDataAdapter, 'function');
assert.equal(typeof normalizeFrontendError, 'function');
assert.equal(typeof createPageController, 'function');
assert.equal(typeof parseRoute, 'function');
assert.equal(ERROR_TYPES.missingScope, 'missing_scope');
assert.equal(PAGE_IDS.board, 'board');

console.log('ok - api barrel exports frontend relay clients');
