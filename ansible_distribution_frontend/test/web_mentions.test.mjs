import assert from 'node:assert/strict';

import {
  activeMentionDids,
  insertMentionAtSelection,
  mentionToken,
  normalizeMentionDids,
} from '../src/web_mentions.mjs';

const alice = { did: 'did:elix:alice', handle: 'alice.elix.cool' };
assert.equal(mentionToken(alice), '@alice.elix.cool');

const inserted = insertMentionAtSelection('Hello world', 6, 11, alice);
assert.deepEqual(inserted, {
  text: 'Hello @alice.elix.cool ',
  cursor: 23,
  token: '@alice.elix.cool',
});

assert.deepEqual(
  activeMentionDids({
    body: 'Hello @alice.elix.cool and @bob.elix.cool.',
    excludingDid: 'did:elix:me',
    selections: [
      { ...alice, token: '@alice.elix.cool' },
      { did: 'did:elix:bob', handle: 'bob.elix.cool', token: '@bob.elix.cool' },
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
