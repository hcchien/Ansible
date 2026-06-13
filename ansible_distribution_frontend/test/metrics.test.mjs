import assert from 'node:assert/strict';
import { createServer as createHttpServer, request as httpRequest } from 'node:http';

import { createFrontendServer } from '../server.mjs';

const relay = createHttpServer((request, response) => {
  if (request.url === '/api/v1/forum-host') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ display_name: 'ok' }));
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
  // /metrics returns Prometheus text with the declared series, even before
  // any traffic.
  const before = await request(`${baseUrl}/metrics`);
  assert.equal(before.status, 200);
  assert.match(before.headers['content-type'], /text\/plain/);
  assert.match(before.body, /# TYPE frontend_requests_total counter/);
  assert.match(before.body, /# TYPE frontend_upstream_requests_total counter/);
  assert.match(before.body, /# TYPE frontend_upstream_errors_total counter/);

  // Exercise an instrumented path: a proxied relay call bumps both the proxy
  // request counter and the upstream call counter.
  const proxied = await request(`${baseUrl}/api/v1/forum-host`);
  assert.equal(proxied.status, 200);

  const after = await request(`${baseUrl}/metrics`);
  assert.match(after.body, /frontend_requests_total\{kind="proxy"\} [1-9][0-9]*/);
  assert.match(after.body, /frontend_upstream_requests_total [1-9][0-9]*/);
} finally {
  await close(frontend);
  await close(relay);
}

console.log('ok - frontend metrics endpoint');

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
