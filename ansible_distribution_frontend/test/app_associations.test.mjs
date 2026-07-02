// OS universal-link association files: fail-closed 404 until configured, then
// well-formed AASA / assetlinks documents scoped to /boards/* share links.
import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';

import { createFrontendServer } from '../server.mjs';

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

function close(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

function get(baseUrl, path) {
  return new Promise((resolve, reject) => {
    const clientRequest = httpRequest(`${baseUrl}${path}`, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;
      });
      response.on('end', () =>
        resolve({ status: response.statusCode, headers: response.headers, body }),
      );
    });
    clientRequest.on('error', reject);
    clientRequest.end();
  });
}

// ── Unconfigured server: both files fail closed ─────────────────────────────
{
  const server = await listen(
    createFrontendServer({
      relayBaseUrl: 'http://127.0.0.1:9',
      appAssociations: { iosAppIds: [], androidPackage: '', androidSha256Certs: [] },
      logger: null,
    }),
  );
  const base = `http://127.0.0.1:${server.address().port}`;

  for (const path of [
    '/.well-known/apple-app-site-association',
    '/apple-app-site-association',
  ]) {
    const response = await get(base, path);
    assert.equal(response.status, 404, `${path} must 404 when unconfigured`);
    assert.equal(JSON.parse(response.body).error, 'universal_links_not_configured');
  }

  const assetlinks = await get(base, '/.well-known/assetlinks.json');
  assert.equal(assetlinks.status, 404);
  assert.equal(JSON.parse(assetlinks.body).error, 'app_links_not_configured');

  await close(server);
}

// ── Configured server: both files serve well-formed documents ───────────────
{
  const server = await listen(
    createFrontendServer({
      relayBaseUrl: 'http://127.0.0.1:9',
      appAssociations: {
        iosAppIds: ['T68YYD5V2Y.com.example.ansibleNode'],
        androidPackage: 'io.trisaura.ansible_node',
        androidSha256Certs: ['04:EE:D4:93'],
      },
      logger: null,
    }),
  );
  const base = `http://127.0.0.1:${server.address().port}`;

  for (const path of [
    '/.well-known/apple-app-site-association',
    '/apple-app-site-association',
  ]) {
    const response = await get(base, path);
    assert.equal(response.status, 200);
    assert.match(response.headers['content-type'] ?? '', /application\/json/);
    const { applinks } = JSON.parse(response.body);
    assert.deepEqual(applinks.details[0].appIDs, ['T68YYD5V2Y.com.example.ansibleNode']);
    assert.deepEqual(applinks.details[0].components, [{ '/': '/boards/*' }]);
    assert.deepEqual(applinks.details[0].paths, ['/boards/*']);
  }

  const assetlinks = await get(base, '/.well-known/assetlinks.json');
  assert.equal(assetlinks.status, 200);
  const [statement] = JSON.parse(assetlinks.body);
  assert.deepEqual(statement.relation, ['delegate_permission/common.handle_all_urls']);
  assert.equal(statement.target.package_name, 'io.trisaura.ansible_node');
  assert.deepEqual(statement.target.sha256_cert_fingerprints, ['04:EE:D4:93']);

  await close(server);
}

console.log('app_associations.test.mjs OK');
