import assert from 'node:assert/strict';
import { createServer as createHttpServer, request as httpRequest } from 'node:http';

import { createFrontendServer } from '../server.mjs';

const relayRequests = [];
const relay = createHttpServer((request, response) => {
  relayRequests.push({
    method: request.method,
    url: request.url,
    authorization: request.headers.authorization,
  });

  if (request.url === '/api/v1/forum-host') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ display_name: 'Relay through frontend server' }));
    return;
  }

  response.writeHead(404, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ error: 'not_found' }));
});

await listen(relay);

// Separate AppView upstream: curated external content must route here, not the
// relay (the contract path is GET /api/v1/boards/:id/external).
const appViewRequests = [];
const appView = createHttpServer((request, response) => {
  appViewRequests.push({ method: request.method, url: request.url });
  response.writeHead(200, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ items: [], next_cursor: null, has_more: false }));
});
await listen(appView);

const frontend = createFrontendServer({
  relayBaseUrl: `http://127.0.0.1:${relay.address().port}`,
  appViewBaseUrl: `http://127.0.0.1:${appView.address().port}`,
  logger: null,
});
await listen(frontend);
const baseUrl = `http://127.0.0.1:${frontend.address().port}`;

try {
  const index = await request(`${baseUrl}/`);
  assert.equal(index.status, 200);
  assert.match(index.body, /<title>Elix<\/title>/);
  assert.match(index.headers['content-type'], /text\/html/);

  const module = await request(`${baseUrl}/src/main.mjs`);
  assert.equal(module.status, 200);
  assert.match(module.body, /createForumUiApp/);
  assert.match(module.headers['content-type'], /text\/javascript/);

  const spaRoute = await request(`${baseUrl}/boards/general`);
  assert.equal(spaRoute.status, 200);
  assert.match(spaRoute.body, /<script type="module" src=".\/src\/main.mjs"><\/script>/);

  const health = await request(`${baseUrl}/healthz`);
  assert.equal(health.status, 200);
  assert.deepEqual(JSON.parse(health.body), {
    ok: true,
    service: 'elix-web-frontend',
  });

  const proxied = await request(`${baseUrl}/api/v1/forum-host`, {
    headers: { authorization: 'Bearer wst_test' },
  });
  assert.equal(proxied.status, 200);
  assert.equal(JSON.parse(proxied.body).display_name, 'Relay through frontend server');
  assert.deepEqual(relayRequests.at(-1), {
    method: 'GET',
    url: '/api/v1/forum-host',
    authorization: 'Bearer wst_test',
  });

  // External content path routes to the AppView upstream, not the relay.
  const relayCountBefore = relayRequests.length;
  const external = await request(`${baseUrl}/api/v1/boards/fediverse-watch/external?limit=20`);
  assert.equal(external.status, 200);
  assert.deepEqual(JSON.parse(external.body).items, []);
  assert.deepEqual(appViewRequests.at(-1), {
    method: 'GET',
    url: '/api/v1/boards/fediverse-watch/external?limit=20',
  });
  assert.equal(relayRequests.length, relayCountBefore, 'external path must not hit the relay');

  // Security headers (incl. HSTS + Permissions-Policy) are applied to responses.
  assert.equal(index.headers['strict-transport-security'], 'max-age=31536000; includeSubDomains; preload');
  assert.match(index.headers['permissions-policy'] ?? '', /geolocation=\(\)/);
  assert.equal(proxied.headers['strict-transport-security'], 'max-age=31536000; includeSubDomains; preload');

  // Proxy rejects an oversized body up front (advertised content-length over the
  // cap) with 413 and never forwards it to the relay.
  const relayCountBeforeBig = relayRequests.length;
  const tooBig = await request(`${baseUrl}/api/v1/forum-host`, {
    method: 'POST',
    headers: {
      'content-type': 'application/octet-stream',
      'content-length': String(11 * 1024 * 1024), // over the 10 MiB default cap
    },
    body: 'x'.repeat(1024),
  });
  assert.equal(tooBig.status, 413);
  assert.equal(JSON.parse(tooBig.body).error, 'payload_too_large');
  assert.equal(relayRequests.length, relayCountBeforeBig, 'oversized body must not reach the relay');
} finally {
  await close(frontend);
  await close(appView);
  await close(relay);
}

console.log('ok - frontend server');

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
}

function close(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

function request(url, options = {}) {
  return new Promise((resolve, reject) => {
    const clientRequest = httpRequest(url, options, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;
      });
      response.on('end', () => {
        resolve({ status: response.statusCode, headers: response.headers, body });
      });
    });
    clientRequest.on('error', reject);
    clientRequest.end(options.body);
  });
}
