import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';

import {
  buildWebPublicationOperation,
  canonicalJson,
  createPasskeySignedThread,
  sha256Hex,
} from '../src/web_publication_client.mjs';

const fixedNow = () => new Date('2026-07-24T08:30:00.000Z');
const operation = await buildWebPublicationOperation({
  cryptoImpl: webcrypto,
  authorDid: 'did:elix:alice',
  targetForumHost: 'https://forum.elix.cool/path-is-not-part-of-origin',
  boardId: 'general',
  boardPolicyVersion: 3,
  title: 'Exact signed title',
  now: fixedNow,
});

assert.equal(operation.target_forum_host, 'https://forum.elix.cool');
assert.equal(operation.action, 'forum.publish');
assert.equal(operation.entity_type, 'thread');
assert.equal(operation.board_policy_version, 3);
assert.equal(operation.payload.title, 'Exact signed title');
assert.equal(operation.payload_hash, await sha256Hex('{"title":"Exact signed title"}', webcrypto));
assert.equal(
  canonicalJson({ z: 1, a: { y: true, x: ['b', 'a'] } }),
  '{"a":{"x":["b","a"],"y":true},"z":1}',
);

const reply = await buildWebPublicationOperation({
  cryptoImpl: webcrypto,
  authorDid: 'did:elix:alice',
  targetForumHost: 'https://forum.elix.cool',
  boardId: 'general',
  boardPolicyVersion: 3,
  action: 'forum.reply',
  entityType: 'post',
  parentId: 'thread-1',
  payload: { body: 'Signed reply' },
  now: fixedNow,
});
assert.equal(reply.action, 'forum.reply');
assert.equal(reply.parent_id, 'thread-1');
assert.equal(reply.payload_hash, await sha256Hex('{"body":"Signed reply"}', webcrypto));
assert.notEqual(
  await sha256Hex(canonicalJson(reply), webcrypto),
  await sha256Hex(canonicalJson({ ...reply, federate: false }), webcrypto),
  'distribution consent is part of the signed operation',
);

for (const action of ['forum.edit', 'forum.delete', 'forum.react']) {
  const candidate = await buildWebPublicationOperation({
    cryptoImpl: webcrypto,
    authorDid: 'did:elix:alice',
    targetForumHost: 'https://forum.elix.cool',
    boardId: 'general',
    boardPolicyVersion: 3,
    action,
    entityType: action === 'forum.react' ? 'reaction' : 'post',
    entityId: `${action}-entity`,
    parentId: 'post-1',
    expectedPreviousRevision: 'rev-1',
    payload: { value: action },
    now: fixedNow,
  });
  assert.equal(candidate.action, action);
  assert.equal(candidate.expected_previous_revision, 'rev-1');
}

const requests = [];
const assertion = {
  id: 'credential-1',
  rawId: Uint8Array.from([1, 2, 3]).buffer,
  type: 'public-key',
  response: {
    clientDataJSON: Uint8Array.from([4, 5]).buffer,
    authenticatorData: Uint8Array.from([6, 7]).buffer,
    signature: Uint8Array.from([8, 9]).buffer,
    userHandle: null,
  },
};

const result = await createPasskeySignedThread({
  relayBaseUrl: 'https://forum.elix.cool',
  fetchImpl: async (url, init) => {
    const body = init?.body ? JSON.parse(init.body) : null;
    requests.push({ url, init, body });

    if (String(url).endsWith('/api/v1/web-publication/challenges')) {
      return jsonResponse(201, {
        challenge_id: 'wpc-1',
        publicKey: {
          challenge: 'AQID',
          rpId: 'forum.elix.cool',
          userVerification: 'required',
          allowCredentials: [{ type: 'public-key', id: 'AQID' }],
        },
      });
    }
    return jsonResponse(202, {
      accepted: true,
      publication: {
        operation_id: body.operation.operation_id,
        operation_hash: body.operation_hash,
        author_proof: { scheme: 'webauthn-p256-sha256' },
      },
    });
  },
  credentials: {
    async get(options) {
      assert.equal(options.publicKey.userVerification, 'required');
      assert.deepEqual([...options.publicKey.challenge], [1, 2, 3]);
      return assertion;
    },
  },
  cryptoImpl: webcrypto,
  authorDid: 'did:elix:alice',
  targetForumHost: 'https://forum.elix.cool',
  boardId: 'general',
  boardPolicyVersion: 3,
  title: 'Signed in browser',
  now: fixedNow,
});

assert.equal(result.accepted, true);
assert.equal(requests.length, 2);
assert.equal(requests[0].init.credentials, 'same-origin');
assert.equal(requests[1].body.challenge_id, 'wpc-1');
assert.deepEqual(requests[1].body.credential.response, {
  clientDataJSON: 'BAU',
  authenticatorData: 'Bgc',
  signature: 'CAk',
  userHandle: null,
});
assert.equal(
  requests[0].body.operation_hash,
  requests[1].body.operation_hash,
  'the exact challenged operation hash must be submitted unchanged',
);

console.log('ok - content-bound passkey web publication client');

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
