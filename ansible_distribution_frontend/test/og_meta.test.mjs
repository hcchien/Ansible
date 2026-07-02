import assert from 'node:assert/strict';
import { createServer as createHttpServer, request as httpRequest } from 'node:http';

import { createFrontendServer } from '../server.mjs';
import {
  buildDescription,
  buildPageMetadata,
  parseSharePath,
  renderMetaTags,
  resolveOrigin,
} from '../src/og_meta.mjs';

// --- Unit: path parsing -----------------------------------------------------

assert.deepEqual(parseSharePath('/boards/general'), {
  kind: 'board',
  boardId: 'general',
});
assert.deepEqual(parseSharePath('/boards/general/threads/thread-9'), {
  kind: 'thread',
  boardId: 'general',
  threadId: 'thread-9',
});
assert.equal(parseSharePath('/'), null);
assert.equal(parseSharePath('/boards'), null);
assert.equal(parseSharePath('/sessions'), null);
console.log('ok - parses board and thread share paths');

// --- Unit: description sanitisation -----------------------------------------

assert.equal(buildDescription('<b>hello</b>   world'), 'hello world');
assert.equal(buildDescription(null), '');
const long = buildDescription('x'.repeat(400));
assert.ok(long.length <= 160, 'description is truncated to ~160 chars');
assert.ok(long.endsWith('…'), 'truncated description ends with an ellipsis');
console.log('ok - strips HTML and truncates descriptions');

// --- Unit: origin resolution ------------------------------------------------

assert.equal(
  resolveOrigin({ headers: { host: 'elix.example' } }),
  'http://elix.example',
);
assert.equal(
  resolveOrigin({
    headers: { host: 'elix.example', 'x-forwarded-proto': 'https' },
  }),
  'https://elix.example',
);
assert.equal(
  resolveOrigin({ headers: {} }, { publicBaseUrl: 'https://share.elix.tw/' }),
  'https://share.elix.tw',
);
console.log('ok - derives the canonical origin from config/host/forwarded headers');

// --- Unit: metadata + escaping ----------------------------------------------

const boards = [
  {
    id: 'general',
    slug: 'general',
    title: 'General <board>',
    description: 'Friendly "general" discussion & more',
  },
];

const boardMeta = buildPageMetadata(
  { kind: 'board', boardId: 'general' },
  { boards, origin: 'https://elix.example' },
);
assert.equal(boardMeta.type, 'website');
assert.equal(boardMeta.canonicalUrl, 'https://elix.example/boards/general');
assert.ok(boardMeta.title.includes('General <board>'));

const boardTags = renderMetaTags(boardMeta);
assert.match(boardTags, /<meta property="og:title" content="General &lt;board&gt; · Elix" \/>/);
assert.match(boardTags, /<meta property="og:url" content="https:\/\/elix\.example\/boards\/general" \/>/);
assert.match(boardTags, /<link rel="canonical" href="https:\/\/elix\.example\/boards\/general" \/>/);
assert.match(boardTags, /<meta property="og:type" content="website" \/>/);
assert.match(boardTags, /<meta property="og:site_name" content="Elix" \/>/);
assert.match(boardTags, /<meta name="twitter:card" content="summary" \/>/);
// The raw angle brackets / ampersand / quotes must be escaped (XSS-safe).
assert.ok(!boardTags.includes('<board>'), 'title angle brackets are escaped');
assert.match(boardTags, /Friendly &quot;general&quot; discussion &amp; more/);
console.log('ok - board metadata emits escaped og/twitter/canonical tags');

const threadMeta = buildPageMetadata(
  { kind: 'thread', boardId: 'general', threadId: 'thread-9' },
  { boards, origin: 'https://elix.example' },
);
assert.equal(threadMeta.type, 'article');
assert.equal(
  threadMeta.canonicalUrl,
  'https://elix.example/boards/general/threads/thread-9',
);
const threadTags = renderMetaTags(threadMeta);
assert.match(threadTags, /<meta property="og:type" content="article" \/>/);
assert.match(
  threadTags,
  /<meta property="og:url" content="https:\/\/elix\.example\/boards\/general\/threads\/thread-9" \/>/,
);
console.log('ok - thread metadata is article-typed with a thread-scoped canonical URL');

// With a relay thread preview, the thread title leads and the first-reply
// excerpt becomes the description; without one, board context remains.
const previewedThreadMeta = buildPageMetadata(
  { kind: 'thread', boardId: 'general', threadId: 'thread-9' },
  {
    boards,
    origin: 'https://elix.example',
    threadPreview: {
      title: '我們在重建什麼樣的網路？',
      excerpt: '便利往往是監控偽裝成的禮物。',
      reply_count: 2,
    },
  },
);
assert.match(previewedThreadMeta.title, /^我們在重建什麼樣的網路？ · /);
assert.equal(previewedThreadMeta.description, '便利往往是監控偽裝成的禮物。');
assert.equal(previewedThreadMeta.type, 'article');
console.log('ok - thread preview supplies thread title + excerpt');

// A preview without an excerpt still upgrades the title but keeps the board
// description fallback.
const titleOnlyPreviewMeta = buildPageMetadata(
  { kind: 'thread', boardId: 'general', threadId: 'thread-9' },
  {
    boards,
    origin: 'https://elix.example',
    threadPreview: { title: 'Title only', excerpt: null },
  },
);
assert.match(titleOnlyPreviewMeta.title, /^Title only · /);
assert.equal(titleOnlyPreviewMeta.description, threadMeta.description);
console.log('ok - preview without excerpt falls back to board description');

// No og:image is fabricated when none is configured.
assert.ok(!boardTags.includes('og:image'), 'og:image omitted without a configured image');
console.log('ok - omits og:image when no image is configured');

// --- Integration: served HTML carries injected tags -------------------------

const relay = createHttpServer((request, response) => {
  if (request.url === '/api/v1/forum-host/boards') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(
      JSON.stringify({
        boards: [
          {
            hosted_board_id: 'general',
            slug: 'general',
            title: 'General <board>',
            description: 'Friendly "general" discussion & more',
          },
        ],
      }),
    );
    return;
  }
  response.writeHead(404, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ error: 'not_found' }));
});

await listen(relay);
const frontend = createFrontendServer({
  relayBaseUrl: `http://127.0.0.1:${relay.address().port}`,
  logger: null,
});
await listen(frontend);
const baseUrl = `http://127.0.0.1:${frontend.address().port}`;

try {
  const boardPage = await request(`${baseUrl}/boards/general`, {
    headers: { host: 'elix.example' },
  });
  assert.equal(boardPage.status, 200);
  assert.match(boardPage.headers['content-type'], /text\/html/);
  // og:title + escaping
  assert.match(
    boardPage.body,
    /<meta property="og:title" content="General &lt;board&gt; · Elix" \/>/,
  );
  // og:url + canonical derived from the request host
  assert.match(
    boardPage.body,
    /<meta property="og:url" content="http:\/\/elix\.example\/boards\/general" \/>/,
  );
  assert.match(
    boardPage.body,
    /<link rel="canonical" href="http:\/\/elix\.example\/boards\/general" \/>/,
  );
  // The SPA still boots — the module script tag is preserved.
  assert.match(boardPage.body, /<script type="module" src=".\/src\/main.mjs"><\/script>/);
  // The static placeholder <title>Elix</title> was replaced (no duplicate).
  assert.equal((boardPage.body.match(/<title>/g) ?? []).length, 1);

  const threadPage = await request(`${baseUrl}/boards/general/threads/thread-9`, {
    headers: { host: 'elix.example' },
  });
  assert.equal(threadPage.status, 200);
  assert.match(threadPage.body, /<meta property="og:type" content="article" \/>/);
  assert.match(
    threadPage.body,
    /<meta property="og:url" content="http:\/\/elix\.example\/boards\/general\/threads\/thread-9" \/>/,
  );

  // Non-share routes are unaffected: home still serves the plain SPA shell.
  const home = await request(`${baseUrl}/`, { headers: { host: 'elix.example' } });
  assert.equal(home.status, 200);
  assert.match(home.body, /<title>Elix<\/title>/);
  assert.ok(!home.body.includes('og:title'), 'home page has no injected og tags');
} finally {
  await close(frontend);
  await close(relay);
}

console.log('ok - serves board/thread pages with injected, escaped OG meta tags');

function listen(server) {
  return new Promise((resolvePromise, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolvePromise();
    });
  });
}

function close(server) {
  return new Promise((resolvePromise, reject) => {
    server.close((error) => (error ? reject(error) : resolvePromise()));
  });
}

function request(url, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const clientRequest = httpRequest(url, options, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;
      });
      response.on('end', () => {
        resolvePromise({ status: response.statusCode, headers: response.headers, body });
      });
    });
    clientRequest.on('error', reject);
    clientRequest.end(options.body);
  });
}
