import assert from 'node:assert/strict';

import {
  createHostedWebThread,
  fetchBoardModerationState,
  fetchBoardDeliberations,
  fetchWebDeliberationResponses,
  fetchForumHostInfo,
  fetchHostedBoards,
  fetchWebModerationActions,
  fetchWebModerationReports,
  submitWebModerationAction,
  submitWebReport,
  submitWebDeliberationVote,
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
    boardId: 'general',
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
  assert.equal(
    requests[0].init.body,
    '{"title":"Hello Forum","board_id":"general"}',
  );
});

test('submits web reports with the relay contract payload (201 created)', async () => {
  const requests = [];
  const result = await submitWebReport({
    relayBaseUrl: 'http://localhost:4001',
    targetKind: 'post',
    targetRef: 'post-201',
    boardId: 'general',
    reasonCode: 'spam',
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(201, {
        report: { id: 41, status: 'open', reason_code: 'spam' },
      });
    },
  });

  assert.equal(requests[0].url, 'http://localhost:4001/api/v1/forum-host/web/reports');
  assert.equal(requests[0].init.credentials, 'same-origin');
  assert.deepEqual(JSON.parse(requests[0].init.body), {
    target_kind: 'post',
    target_ref: 'post-201',
    board_id: 'general',
    reason_code: 'spam',
    note: null,
  });
  assert.deepEqual(result, {
    report: { id: 41, status: 'open', reason_code: 'spam' },
    duplicate: false,
  });
});

test('marks an HTTP 200 report response as a duplicate collapse', async () => {
  const result = await submitWebReport({
    relayBaseUrl: 'http://localhost:4001',
    targetKind: 'thread',
    targetRef: 'thread-9',
    boardId: 'general',
    reasonCode: 'other',
    note: '需要附註',
    fetchImpl: async () =>
      jsonResponse(200, { report: { id: 41, status: 'open' } }),
  });

  assert.deepEqual(result, {
    report: { id: 41, status: 'open' },
    duplicate: true,
  });
});

test('fetches the moderation queue and audit trail with cookie auth', async () => {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, init });
    return url.includes('/reports')
      ? jsonResponse(200, { reports: [] })
      : jsonResponse(200, { actions: [] });
  };

  await fetchWebModerationReports({
    relayBaseUrl: 'http://localhost:4001',
    fetchImpl,
  });
  await fetchWebModerationActions({
    relayBaseUrl: 'http://localhost:4001',
    fetchImpl,
  });

  assert.deepEqual(
    requests.map((request) => request.url),
    [
      'http://localhost:4001/api/v1/forum-host/web/moderation/reports?status=open',
      'http://localhost:4001/api/v1/forum-host/web/moderation/actions',
    ],
  );
  for (const request of requests) {
    assert.equal(request.init.credentials, 'same-origin');
  }
});

test('submits moderation actions with the relay contract payload', async () => {
  const requests = [];
  await submitWebModerationAction({
    relayBaseUrl: 'http://localhost:4001',
    action: 'lock_thread',
    targetRef: 'thread-9',
    boardId: 'general',
    reasonCode: 'harassment',
    reportId: 42,
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(201, { action: { id: 8 } });
    },
  });

  assert.equal(
    requests[0].url,
    'http://localhost:4001/api/v1/forum-host/web/moderation/actions',
  );
  assert.equal(requests[0].init.credentials, 'same-origin');
  assert.deepEqual(JSON.parse(requests[0].init.body), {
    action: 'lock_thread',
    target_ref: 'thread-9',
    board_id: 'general',
    reason_code: 'harassment',
    report_id: 42,
  });
});

test('reads the public board moderation state without credentials', async () => {
  const requests = [];
  const state = await fetchBoardModerationState({
    relayBaseUrl: 'http://localhost:4001',
    boardId: 'general',
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(200, { removed_posts: [], locked_threads: [] });
    },
  });

  assert.equal(
    requests[0].url,
    'http://localhost:4001/api/v1/forum-host/boards/general/moderation-state',
  );
  assert.equal(requests[0].init.credentials, 'omit');
  assert.deepEqual(state, { removed_posts: [], locked_threads: [] });
});

test('reads deliberations publicly and keeps own responses on the web-session rail', async () => {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, init });
    return url.endsWith('/responses/mine')
      ? jsonResponse(200, { responses: { 's-1': { stance: 'agree', last_intent_id: 'v-1' } } })
      : jsonResponse(200, { deliberations: [] });
  };
  await fetchBoardDeliberations({
    relayBaseUrl: 'http://localhost:4001',
    boardId: 'general',
    fetchImpl,
  });
  const own = await fetchWebDeliberationResponses({
    relayBaseUrl: 'http://localhost:4001',
    boardId: 'general',
    deliberationId: 'd-1',
    fetchImpl,
  });
  assert.deepEqual(own.responses['s-1'], { stance: 'agree', last_intent_id: 'v-1' });
  assert.equal(requests[0].init.credentials, 'omit');
  assert.equal(requests[1].init.credentials, 'same-origin');
});

test('updates a deliberation response with the prior intent id', async () => {
  const requests = [];
  await submitWebDeliberationVote({
    relayBaseUrl: 'http://localhost:4001',
    boardId: 'general',
    deliberationId: 'd-1',
    statementId: 's-1',
    stance: 'disagree',
    supersedesIntentId: 'v-1',
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(200, { response: { stance: 'disagree', last_intent_id: 'v-2' } });
    },
  });
  assert.equal(requests[0].init.method, 'PUT');
  assert.deepEqual(JSON.parse(requests[0].init.body), {
    stance: 'disagree',
    supersedes_intent_id: 'v-1',
  });
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
