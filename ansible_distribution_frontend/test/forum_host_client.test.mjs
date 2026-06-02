import assert from 'node:assert/strict';

import {
  createHostedWebThread,
  fetchForumHostInfo,
  fetchHostedBoards,
} from '../src/forum_host_client.mjs';
import { WEB_SESSION_TOKEN_KEY } from '../src/web_session_client.mjs';

class MemoryStorage {
  constructor(entries = []) {
    this.values = new Map(entries);
  }

  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }

  removeItem(key) {
    this.values.delete(key);
  }
}

const tests = [];

function test(name, body) {
  tests.push({ name, body });
}

test('loads Forum Host metadata and hosted boards through public read APIs', async () => {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, init });

    if (url.endsWith('/api/v1/forum-host')) {
      return jsonResponse(200, {
        forum_host_id: 'host-local-dev',
        capabilities: { create_threads: true },
      });
    }

    return jsonResponse(200, {
      boards: [{ hosted_board_id: 'general', title: 'General' }],
    });
  };

  const host = await fetchForumHostInfo({
    relayBaseUrl: 'http://localhost:4001/',
    fetchImpl,
  });
  const boards = await fetchHostedBoards({
    relayBaseUrl: 'http://localhost:4001/',
    fetchImpl,
  });

  assert.equal(host.forum_host_id, 'host-local-dev');
  assert.deepEqual(boards.boards, [{ hosted_board_id: 'general', title: 'General' }]);
  assert.deepEqual(
    requests.map((request) => request.url),
    [
      'http://localhost:4001/api/v1/forum-host',
      'http://localhost:4001/api/v1/forum-host/boards',
    ],
  );
  for (const request of requests) {
    assert.equal(headerValue(request.init.headers, 'authorization'), undefined);
    assert.equal(request.init.credentials, 'omit');
  }
});

test('creates hosted web threads with the httpOnly session cookie', async () => {
  const requests = [];
  const storage = new MemoryStorage([[WEB_SESSION_TOKEN_KEY, 'wst_legacy']]);
  const result = await createHostedWebThread({
    relayBaseUrl: 'http://localhost:4001',
    storage,
    title: 'Hello Forum',
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(202, {
        accepted: true,
        subject_did: 'did:plc:abc',
        trust_tier: 'self_custody_did',
      });
    },
  });

  assert.deepEqual(result, {
    accepted: true,
    subject_did: 'did:plc:abc',
    trust_tier: 'self_custody_did',
  });
  assert.equal(
    requests[0].url,
    'http://localhost:4001/api/v1/forum-host/web/threads',
  );
  assert.equal(headerValue(requests[0].init.headers, 'authorization'), undefined);
  assert.equal(requests[0].init.credentials, 'same-origin');
  assert.equal(requests[0].init.body, '{"title":"Hello Forum"}');
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

function headerValue(headers, name) {
  const normalizedName = name.toLowerCase();

  for (const [key, value] of Object.entries(headers ?? {})) {
    if (key.toLowerCase() === normalizedName) {
      return value;
    }
  }

  return undefined;
}

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
