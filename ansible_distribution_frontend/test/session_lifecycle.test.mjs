import assert from 'node:assert/strict';

import {
  DEFAULT_SESSION_VIEW_MODEL,
  createSessionLifecycle,
  mapRelayErrorToSessionError,
} from '../src/session_lifecycle.mjs';
import { RelayApiError } from '../src/relay_api_client.mjs';
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

test('restores public mode when the httpOnly cookie session is absent', async () => {
  let fetchCount = 0;
  const lifecycle = createSessionLifecycle({
    relayBaseUrl: 'http://localhost:4001',
    webOrigin: 'http://localhost:5173',
    storage: new MemoryStorage(),
    webSessionClient: {
      async fetchCurrentWebSession() {
        fetchCount += 1;
        throw new RelayApiError('invalid_web_session', {
          status: 401,
          code: 'invalid_web_session',
        });
      },
    },
  });

  const state = await lifecycle.restore();

  assert.equal(fetchCount, 1);
  assert.deepEqual(state.viewModel, DEFAULT_SESSION_VIEW_MODEL);
});

test('restores an app-approved DID session into a capability view model', async () => {
  const storage = new MemoryStorage([[WEB_SESSION_TOKEN_KEY, 'wst_current']]);
  const lifecycle = createSessionLifecycle({
    relayBaseUrl: 'http://localhost:4001',
    webOrigin: 'http://localhost:5173',
    storage,
    webSessionClient: {
      async fetchCurrentWebSession({ relayBaseUrl }) {
        assert.equal(relayBaseUrl, 'http://localhost:4001');
        return {
          session_id: 'wsi_current',
          subject_did: 'did:plc:abc',
          identity_aliases: ['did:elix:legacy-abc'],
          trust_tier: 'self_custody_did',
          scopes: ['forum:read', 'forum:post', 'session:revoke'],
          expires_at: '2026-05-12T01:00:00Z',
        };
      },
    },
  });

  const state = await lifecycle.restore();

  assert.equal(state.status, 'authenticated');
  assert.deepEqual(state.viewModel, {
    mode: 'app_approved_did',
    authenticated: true,
    trustTier: 'self_custody_did',
    subjectDid: 'did:plc:abc',
    identityAliases: ['did:elix:legacy-abc'],
    scopes: ['forum:read', 'forum:post', 'session:revoke'],
    expiresAt: '2026-05-12T01:00:00Z',
    challenge: null,
    error: null,
    capabilities: {
      canRead: true,
      canPost: true,
      canReply: false,
      canReact: false,
      canEdit: false,
      canDelete: false,
      canRevoke: true,
      canManageProfile: false,
    },
  });
});

test('starts app login and exposes pending challenge state for the future UI', async () => {
  const calls = [];
  const lifecycle = createSessionLifecycle({
    relayBaseUrl: 'http://localhost:4001/',
    webOrigin: 'http://localhost:5173',
    storage: new MemoryStorage(),
    webSessionClient: {
      async createWebSessionChallenge(params) {
        calls.push(params);
        return {
          challenge_id: 'wsc_123',
          expires_at: '2026-05-11T13:00:00Z',
          deep_link: 'trisaura://web-session/approve?challenge_id=wsc_123',
          qr_payload: 'trisaura://web-session/approve?challenge_id=wsc_123',
        };
      },
    },
  });

  const state = await lifecycle.startAppLogin();

  assert.equal(calls[0].relayOrigin, 'http://localhost:4001');
  assert.deepEqual(calls[0].scopes, [
    'forum:read',
    'forum:post',
    'forum:reply',
    'forum:edit',
    'forum:delete',
    'forum:react',
    'identity:display',
  ]);
  assert.equal(state.status, 'login_pending');
  assert.deepEqual(state.viewModel.scopes, [
    'forum:read',
    'forum:post',
    'forum:reply',
    'forum:edit',
    'forum:delete',
    'forum:react',
    'identity:display',
  ]);
  assert.deepEqual(state.viewModel.challenge, {
    challengeId: 'wsc_123',
    expiresAt: '2026-05-11T13:00:00Z',
    deepLink: 'trisaura://web-session/approve?challenge_id=wsc_123',
    qrPayload: 'trisaura://web-session/approve?challenge_id=wsc_123',
    continuePolling: true,
  });
});

test('polls approved challenges, then loads the current cookie-backed session view model', async () => {
  const storage = new MemoryStorage();
  const lifecycle = createSessionLifecycle({
    relayBaseUrl: 'http://localhost:4001',
    webOrigin: 'http://localhost:5173',
    storage,
    webSessionClient: {
      async createWebSessionChallenge() {
        return {
          challenge_id: 'wsc_approved',
          expires_at: '2026-05-11T13:00:00Z',
          deep_link: 'trisaura://web-session/approve?challenge_id=wsc_approved',
          qr_payload: 'trisaura://web-session/approve?challenge_id=wsc_approved',
        };
      },
      async fetchChallengeStatus() {
        return {
          status: 'approved',
          challenge_id: 'wsc_approved',
          trust_tier: 'self_custody_did',
        };
      },
      async fetchCurrentWebSession() {
        return {
          session_id: 'wsi_new',
          subject_did: 'did:plc:new',
          trust_tier: 'self_custody_did',
          scopes: ['forum:read', 'forum:post', 'forum:reply'],
          expires_at: '2026-05-12T01:00:00Z',
        };
      },
    },
  });

  await lifecycle.startAppLogin();
  const state = await lifecycle.pollLoginChallenge();

  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);
  assert.equal(state.status, 'authenticated');
  assert.equal(state.viewModel.capabilities.canPost, true);
  assert.equal(state.viewModel.capabilities.canReply, true);
});

test('clears token and returns public mode after revoking the current session', async () => {
  const storage = new MemoryStorage([[WEB_SESSION_TOKEN_KEY, 'wst_current']]);
  const lifecycle = createSessionLifecycle({
    relayBaseUrl: 'http://localhost:4001',
    webOrigin: 'http://localhost:5173',
    storage,
    webSessionClient: {
      async revokeWebSession() {
        storage.removeItem(WEB_SESSION_TOKEN_KEY);
        return { revoked: true };
      },
    },
  });

  const state = await lifecycle.revokeCurrentSession();

  assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);
  assert.equal(state.status, 'signed_out');
  assert.deepEqual(state.viewModel, DEFAULT_SESSION_VIEW_MODEL);
});

test('maps relay and network failures to semantic session errors', () => {
  assert.deepEqual(
    mapRelayErrorToSessionError(
      new RelayApiError('invalid_web_session', {
        status: 401,
        code: 'invalid_web_session',
      }),
    ),
    { type: 'unauthenticated', message: 'invalid_web_session', retryable: true },
  );
  assert.deepEqual(
    mapRelayErrorToSessionError(
      new RelayApiError('missing_scope', { status: 403, code: 'missing_scope' }),
    ),
    { type: 'missing_scope', message: 'missing_scope', retryable: false },
  );
  assert.deepEqual(
    mapRelayErrorToSessionError(new TypeError('Failed to fetch')),
    { type: 'network_unavailable', message: 'Failed to fetch', retryable: true },
  );
});

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
