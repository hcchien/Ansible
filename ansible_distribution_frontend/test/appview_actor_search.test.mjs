import assert from 'node:assert/strict';

import { searchActors } from '../src/appview_client.mjs';

let requestedUrl = null;
const response = await searchActors({
  appViewBaseUrl: 'https://appview.example',
  query: '@alice lin',
  limit: 10,
  fetchImpl: async (url) => {
    requestedUrl = String(url);
    return new Response(JSON.stringify({
      items: [{ did: 'did:elix:alice', handle: 'alice.elix.cool' }],
    }), { status: 200 });
  },
});

assert.equal(
  requestedUrl,
  'https://appview.example/api/v1/search/actors?q=alice+lin&limit=10',
);
assert.equal(response.items[0].did, 'did:elix:alice');

console.log('ok - AppView people search resolves public mention profiles');
