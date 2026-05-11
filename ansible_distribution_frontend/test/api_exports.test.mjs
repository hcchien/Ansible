import assert from 'node:assert/strict';

import {
  createHostedWebThread,
  createRelayApiClient,
  createSessionLifecycle,
  createWebSessionChallenge,
  fetchForumHostInfo,
  fetchHostedBoards,
  listWebSessions,
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

console.log('ok - api barrel exports frontend relay clients');
