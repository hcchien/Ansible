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

test('returns approved state without storing anything in localStorage (cookie set by server)', () => {
  const storage = new MemoryStorage();
  const result = resolveChallengePollResult(
    {
      status: 'approved',
      challenge_id: 'wsc_123',
      // session_token is no longer returned by the server — cookie is set instead
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
  // No token must be stored in localStorage — cookie is managed by the browser
  assert.equal(storage.length, 0);
});

test('does not clear localStorage for rejected and expired challenges (no token was stored)', () => {
  const storage = new MemoryStorage();

  assert.deepEqual(resolveChallengePollResult({ status: 'rejected' }, storage), {
    state: 'rejected',
    continuePolling: false,
    authenticated: false,
    retryable: true,
  });
  assert.equal(storage.length, 0);

  assert.deepEqual(resolveChallengePollResult({ status: 'expired' }, storage), {
    state: 'expired',
    continuePolling: false,
    authenticated: false,
    retryable: true,
  });
  assert.equal(storage.length, 0);
});

test('loads current and active web sessions via cookie-authenticated relay APIs', async () => {
  const storage = new MemoryStorage();
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, init });

    if (url.endsWith('/api/v1/web-sessions/me')) {
      return jsonResponse(200, {
        session_id: 'wsi_current',
        subject_did: 'did:plc:abc',
        trust_tier: 'self_custody_did',
      });
    }

    return jsonResponse(200, {
      sessions: [{ session_id: 'wsi_current', trust_tier: 'self_custody_did' }],
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
    { session_id: 'wsi_current', trust_tier: 'self_custody_did' },
  ]);
  assert.deepEqual(
    requests.map((request) => request.url),
    [
      'http://localhost:4001/api/v1/web-sessions/me',
      'http://localhost:4001/api/v1/web-sessions',
    ],
  );
  // No Authorization header — authentication is via httpOnly session cookie
  assert.equal(requests[0].init.headers.authorization, undefined);
  // credentials: 'same-origin' ensures the browser sends the cookie automatically
  assert.equal(requests[0].init.credentials, 'same-origin');
});

test('revokes web sessions without clearing localStorage (cookie cleared by server)', async () => {
  const storage = new MemoryStorage();
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
  // No Authorization header — authentication is via httpOnly session cookie
  assert.equal(requests[0].init.headers.authorization, undefined);
  assert.equal(requests[0].init.credentials, 'same-origin');
  assert.equal(requests[0].init.body, '{}');
  // localStorage is untouched — the relay clears the httpOnly cookie
  assert.equal(storage.length, 0);
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
