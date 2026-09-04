import assert from 'node:assert/strict';

import {
  activeMentionDids,
  insertMentionAtSelection,
  mentionToken,
  normalizeMentionDids,
} from '../src/web_mentions.mjs';

const alice = { did: 'did:elix:alice', handle: 'alice.elix.cool', displayName: 'Alice' };
assert.equal(mentionToken(alice), '@Alice');
assert.equal(mentionToken(
  { did: 'did:elix:alice-two', handle: 'alice.two', displayName: 'Alice' },
  { selections: [{ ...alice, token: '@Alice' }] },
), '@Alice (@alice.two)');

const inserted = insertMentionAtSelection('Hello world', 6, 11, alice);
assert.deepEqual(inserted, {
  text: 'Hello @Alice ',
  cursor: 13,
  token: '@Alice',
});

assert.deepEqual(
  activeMentionDids({
    body: 'Hello @Alice and @Bob.',
    excludingDid: 'did:elix:me',
    selections: [
      { ...alice, token: '@Alice' },
      { did: 'did:elix:bob', handle: 'bob.elix.cool', displayName: 'Bob', token: '@Bob' },
      { did: 'did:elix:typed-only', token: '@not-present.elix.cool' },
    ],
  }),
  ['did:elix:alice', 'did:elix:bob'],
);

assert.deepEqual(
  normalizeMentionDids(
    ['did:elix:alice', 'did:elix:me', 'not-a-did', 'did:elix:alice'],
    { excludingDid: 'did:elix:me' },
  ),
  ['did:elix:alice'],
);

console.log('ok - Web mentions bind visible tokens to explicit public DIDs');
