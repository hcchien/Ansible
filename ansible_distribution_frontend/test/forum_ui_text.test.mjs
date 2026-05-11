import assert from 'node:assert/strict';

import {
  describeError,
  formatExpiry,
  formatScope,
  shortIdentity,
  trustTierLabel,
} from '../src/forum_ui_text.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';

assert.equal(shortIdentity(null), 'Anonymous');
assert.equal(shortIdentity('did:plc:fixtureabcdef'), 'did:plc...abcdef');
assert.equal(trustTierLabel('self_custody_did'), 'Self-custody DID');
assert.equal(trustTierLabel('anonymous'), 'Anonymous');
assert.equal(formatScope('forum:post'), 'Post threads');
assert.equal(formatScope('identity:display'), 'Display identity');
assert.equal(formatExpiry('2026-05-12T01:00:00Z'), '2026-05-12 01:00 UTC');

assert.deepEqual(
  describeError({
    type: ERROR_TYPES.missingScope,
    detail: { requiredScope: 'forum:post' },
  }),
  {
    tone: 'warning',
    title: 'Sign in required',
    message: 'This action needs the Post threads scope.',
  },
);

assert.deepEqual(
  describeError({ type: ERROR_TYPES.missingScope }),
  {
    tone: 'warning',
    title: 'Sign in required',
    message: 'This action needs an additional forum scope.',
  },
);

assert.deepEqual(
  describeError({ type: ERROR_TYPES.unauthenticated }),
  {
    tone: 'danger',
    title: 'Session unavailable',
    message: 'Start a new app-approved browser session to continue.',
  },
);

console.log('ok - forum UI text helpers');
