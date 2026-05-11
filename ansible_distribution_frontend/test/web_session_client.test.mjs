import assert from 'node:assert/strict';

import {
  TRUST_TIERS,
  classifyTrustTier,
  fetchCurrentWebSession,
  listWebSessions,
  revokeWebSession,
  resolveChallengePollResult,
  WEB_SESSION_TOKEN_KEY,
} from '../src/web_session_client.mjs';

class MemoryStorage {
  constructor() {
    this.values = new Map();
  }

  get length() {
    return this.values.size;
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

  keys() {
    return Array.from(this.values.keys());
  }
}

const tests = [];

function test(name, body) {
  tests.push({ name, body });
}

test('keeps basic web, passkey web, and app-approved DID tiers distinct', () => {
  assert.deepEqual(classifyTrustTier(TRUST_TIERS.basicWeb), {
    trustTier: 'basic_web',
    canUseHostedWebAccount: true,
    isPasskeyBacked: false,
    isSelfCustodyDid: false,
  });

  assert.deepEqual(classifyTrustTier(TRUST_TIERS.webPasskey), {
    trustTier: 'web_passkey',
    canUseHostedWebAccount: true,
    isPasskeyBacked: true,
    isSelfCustodyDid: false,
  });

  assert.deepEqual(classifyTrustTier(TRUST_TIERS.selfCustodyDid), {
    trustTier: 'self_custody_did',
    canUseHostedWebAccount: false,
    isPasskeyBacked: false,
    isSelfCustodyDid: true,
  });
});

test('continues polling pending challenges without storing identity state', () => {
  const storage = new MemoryStorage();
  const result = resolveChallengePollResult(
    { status: 'pending', challenge_id: 'wsc_123' },
    storage,
  );

  assert.deepEqual(result, {
    state: 'pending',
    continuePolling: true,
    authenticated: false,
    retryable: false,
  });
  assert.equal(storage.length, 0);
});

test('stores only the relay-issued token for approved challenges', () => {
  const storage = new MemoryStorage();
  const result = resolveChallengePollResult(
    {
      status: 'approved',
      challenge_id: 'wsc_123',
      session_token: 'wst_abc',
      subject_did: 'did:plc:abc',
      trust_tier: 'self_custody_did',
    },
    storage,
  );

  assert.deepEqual(result, {
    state: 'approved',
    continuePolling: false,
    authenticated: true,
    retryable: false,
    trustTier: 'self_custody_did',
  });
  assert.deepEqual(storage.keys(), [WEB_SESSION_TOKEN_KEY]);
  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), 'wst_abc');
});

test('clears token state for rejected and expired challenges', () => {
  const storage = new MemoryStorage();
  storage.setItem(WEB_SESSION_TOKEN_KEY, 'old-token');

  assert.deepEqual(resolveChallengePollResult({ status: 'rejected' }, storage), {
    state: 'rejected',
    continuePolling: false,
    authenticated: false,
    retryable: true,
  });
  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);

  storage.setItem(WEB_SESSION_TOKEN_KEY, 'old-token');
  assert.deepEqual(resolveChallengePollResult({ status: 'expired' }, storage), {
    state: 'expired',
    continuePolling: false,
    authenticated: false,
    retryable: true,
  });
  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);
});

test('loads current and active web sessions through authenticated relay APIs', async () => {
  const storage = new MemoryStorage();
  storage.setItem(WEB_SESSION_TOKEN_KEY, 'wst_current');
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, init });

    if (url.endsWith('/api/v1/web-sessions/me')) {
      return jsonResponse(200, {
        session_token: 'wst_current',
        subject_did: 'did:plc:abc',
        trust_tier: 'self_custody_did',
      });
    }

    return jsonResponse(200, {
      sessions: [{ session_token: 'wst_current', trust_tier: 'self_custody_did' }],
    });
  };

  const current = await fetchCurrentWebSession({
    relayBaseUrl: 'http://localhost:4001/',
    storage,
    fetchImpl,
  });
  const sessions = await listWebSessions({
    relayBaseUrl: 'http://localhost:4001/',
    storage,
    fetchImpl,
  });

  assert.equal(current.subject_did, 'did:plc:abc');
  assert.deepEqual(sessions.sessions, [
    { session_token: 'wst_current', trust_tier: 'self_custody_did' },
  ]);
  assert.deepEqual(
    requests.map((request) => request.url),
    [
      'http://localhost:4001/api/v1/web-sessions/me',
      'http://localhost:4001/api/v1/web-sessions',
    ],
  );
  assert.equal(requests[0].init.headers.authorization, 'Bearer wst_current');
});

test('revokes web sessions and clears local token when revoking the current session', async () => {
  const storage = new MemoryStorage();
  storage.setItem(WEB_SESSION_TOKEN_KEY, 'wst_current');
  const requests = [];

  const result = await revokeWebSession({
    relayBaseUrl: 'http://localhost:4001',
    storage,
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(200, { revoked: true });
    },
  });

  assert.deepEqual(result, { revoked: true });
  assert.equal(requests[0].url, 'http://localhost:4001/api/v1/web-sessions/revoke');
  assert.equal(requests[0].init.headers.authorization, 'Bearer wst_current');
  assert.equal(requests[0].init.body, '{}');
  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);
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
