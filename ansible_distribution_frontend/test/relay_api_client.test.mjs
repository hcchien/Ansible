import assert from 'node:assert/strict';

import {
  RelayApiError,
  createRelayApiClient,
} from '../src/relay_api_client.mjs';
import { WEB_SESSION_TOKEN_KEY } from '../src/web_session_client.mjs';

class MemoryStorage {
  constructor(entries = []) {
    this.values = new Map(entries);
  }

  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }

  setItem(key, value) {
    this.values.set(key, String(value));
  }

  removeItem(key) {
    this.values.delete(key);
  }
}

const tests = [];

function test(name, body) {
  tests.push({ name, body });
}

test('sends JSON requests against a trimmed relay base URL', async () => {
  const requests = [];
  const client = createRelayApiClient({
    relayBaseUrl: 'http://localhost:4001/',
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(201, { ok: true });
    },
  });

  const body = await client.postJson('/api/v1/example', { name: 'Ada' });

  assert.deepEqual(body, { ok: true });
  assert.equal(requests[0].url, 'http://localhost:4001/api/v1/example');
  assert.equal(requests[0].init.method, 'POST');
  assert.equal(requests[0].init.headers['content-type'], 'application/json');
  assert.equal(requests[0].init.body, '{"name":"Ada"}');
});

test('uses httpOnly cookie credentials for authenticated requests', async () => {
  const requests = [];
  const storage = new MemoryStorage([[WEB_SESSION_TOKEN_KEY, 'wst_test']]);
  const client = createRelayApiClient({
    relayBaseUrl: 'http://localhost:4001',
    storage,
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(200, { session_id: 'wsi_test' });
    },
  });

  await client.getJson('/api/v1/web-sessions/me', { authenticated: true });

  assert.equal(requests[0].init.headers.authorization, undefined);
  assert.equal(requests[0].init.credentials, 'same-origin');
});

test('postJson uses same-origin credentials and no legacy bearer storage', async () => {
  const requests = [];
  const client = createRelayApiClient({
    relayBaseUrl: 'http://localhost:4001',
    storage: { getItem: () => 'legacy-token' },
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(200, { ok: true });
    },
  });

  await client.postJson('/api/v1/forum-host/web/threads', { title: 'Hello' });

  assert.equal(requests[0].init.credentials, 'same-origin');
  assert.equal(requests[0].init.headers.authorization, undefined);
});

test('does not read or clear legacy stored tokens when unauthorized', async () => {
  const storage = new MemoryStorage([[WEB_SESSION_TOKEN_KEY, 'wst_old']]);
  const client = createRelayApiClient({
    relayBaseUrl: 'http://localhost:4001',
    storage,
    fetchImpl: async () => jsonResponse(401, { error: 'invalid_web_session' }),
  });

  await assert.rejects(
    () => client.getJson('/api/v1/web-sessions/me', { authenticated: true }),
    (error) => {
      assert.equal(error instanceof RelayApiError, true);
      assert.equal(error.status, 401);
      assert.equal(error.code, 'invalid_web_session');
      return true;
    },
  );
  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), 'wst_old');
});

test('authenticated requests still reach the relay when no legacy token exists', async () => {
  let fetchCount = 0;
  const client = createRelayApiClient({
    relayBaseUrl: 'http://localhost:4001',
    storage: new MemoryStorage(),
    fetchImpl: async () => {
      fetchCount += 1;
      return jsonResponse(200, { ok: true });
    },
  });

  await client.postJson('/api/v1/forum-host/web/threads', {}, { authenticated: true });
  assert.equal(fetchCount, 1);
});

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() {
      return body;
    },
  };
}

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
