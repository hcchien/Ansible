import assert from 'node:assert/strict';

import {
  DEFAULT_LOGIN_SCOPES,
  createForumLoginController,
} from '../src/forum_login_app.mjs';
import { WEB_SESSION_TOKEN_KEY } from '../src/web_session_client.mjs';

class MemoryStorage {
  constructor() {
    this.values = new Map();
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

test('starts an app login challenge with forum scopes', async () => {
  const calls = [];
  const controller = createForumLoginController({
    relayBaseUrl: 'http://localhost:4001/',
    webOrigin: 'http://localhost:5173',
    storage: new MemoryStorage(),
    client: {
      async createWebSessionChallenge(params) {
        calls.push(params);
        return {
          challenge_id: 'wsc_test',
          expires_at: '2026-05-11T12:45:00Z',
          deep_link:
            'trisaura://web-session/approve?challenge_id=wsc_test&relay_origin=http%3A%2F%2Flocalhost%3A4001',
          qr_payload:
            'trisaura://web-session/approve?challenge_id=wsc_test&relay_origin=http%3A%2F%2Flocalhost%3A4001',
        };
      },
    },
  });

  const state = await controller.startLogin();

  assert.deepEqual(calls, [
    {
      relayBaseUrl: 'http://localhost:4001/',
      relayOrigin: 'http://localhost:4001',
      webOrigin: 'http://localhost:5173',
      scopes: DEFAULT_LOGIN_SCOPES,
    },
  ]);
  assert.equal(state.status, 'pending');
  assert.equal(state.challenge.challengeId, 'wsc_test');
  assert.equal(state.challenge.deepLink.startsWith('trisaura://'), true);
});

test('uses the relay httpOnly cookie after challenge approval', async () => {
  const storage = new MemoryStorage();
  const controller = createForumLoginController({
    relayBaseUrl: 'http://localhost:4001',
    webOrigin: 'http://localhost:5173',
    storage,
    client: {
      async createWebSessionChallenge() {
        return {
          challenge_id: 'wsc_test',
          expires_at: '2026-05-11T12:45:00Z',
          deep_link: 'trisaura://web-session/approve?challenge_id=wsc_test',
          qr_payload: 'trisaura://web-session/approve?challenge_id=wsc_test',
        };
      },
      async fetchChallengeStatus({ challengeId }) {
        assert.equal(challengeId, 'wsc_test');
        return {
          status: 'approved',
          challenge_id: 'wsc_test',
          trust_tier: 'self_custody_did',
        };
      },
    },
  });

  await controller.startLogin();
  const state = await controller.pollOnce();

  assert.equal(state.status, 'approved');
  assert.equal(state.authenticated, true);
  assert.equal(state.trustTier, 'self_custody_did');
  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);
});

test('sends forum write smoke request with the httpOnly session cookie', async () => {
  const storage = new MemoryStorage();
  const requests = [];
  const controller = createForumLoginController({
    relayBaseUrl: 'http://localhost:4001/',
    webOrigin: 'http://localhost:5173',
    storage,
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return {
        ok: true,
        status: 202,
        async json() {
          return {
            accepted: true,
            subject_did: 'did:plc:abc',
            trust_tier: 'self_custody_did',
          };
        },
      };
    },
  });

  const response = await controller.createThreadSmoke({
    title: 'Login challenge smoke test',
  });

  assert.deepEqual(response, {
    accepted: true,
    subject_did: 'did:plc:abc',
    trust_tier: 'self_custody_did',
  });
  assert.equal(
    requests[0].url,
    'http://localhost:4001/api/v1/forum-host/web/threads',
  );
  assert.equal(requests[0].init.headers.authorization, undefined);
  assert.equal(requests[0].init.credentials, 'same-origin');
});

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
