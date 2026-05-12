import assert from 'node:assert/strict';

import {
  describeError,
  formatExpiry,
  formatScope,
  shortIdentity,
  trustTierLabel,
} from '../src/forum_ui_text.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';

assert.equal(shortIdentity(null), '匿名');
assert.equal(shortIdentity('did:plc:fixtureabcdef'), 'did:plc...abcdef');
assert.equal(trustTierLabel('self_custody_did'), '自持有 DID');
assert.equal(trustTierLabel('anonymous'), '匿名');
assert.equal(formatScope('forum:post'), '發布討論串');
assert.equal(formatScope('identity:display'), '顯示身分');
assert.equal(formatExpiry('2026-05-12T01:00:00Z'), '2026-05-12 01:00 UTC');

assert.deepEqual(
  describeError({
    type: ERROR_TYPES.missingScope,
    detail: { requiredScope: 'forum:post' },
  }),
  {
    tone: 'warning',
    title: '需要登入',
    message: '這個動作需要「發布討論串」權限。',
  },
);

assert.deepEqual(
  describeError({ type: ERROR_TYPES.missingScope }),
  {
    tone: 'warning',
    title: '需要登入',
    message: '這個動作需要額外的 forum 權限。',
  },
);

assert.deepEqual(
  describeError({ type: ERROR_TYPES.unauthenticated }),
  {
    tone: 'danger',
    title: '工作階段不可用',
    message: '請重新建立由 app 核准的瀏覽器工作階段。',
  },
);

console.log('ok - forum UI text helpers');
