import { RelayApiError } from './relay_api_client.mjs';
import { WEB_SESSION_TOKEN_KEY } from './web_session_client.mjs';
import { ERROR_TYPES } from './error_taxonomy.mjs';

export const CONTRACT_FIXTURES = Object.freeze({
  sessions: Object.freeze({
    anonymous: Object.freeze({
      trust_tier: 'anonymous',
      scopes: [],
    }),
    approvedDid: Object.freeze({
      session_id: 'wsi_fixture',
      subject_did: 'did:plc:fixture',
      trust_tier: 'self_custody_did',
      scopes: Object.freeze([
        'forum:read',
        'forum:post',
        'forum:reply',
        'identity:display',
        'session:revoke',
      ]),
      expires_at: '2026-05-12T01:00:00Z',
    }),
    expired: Object.freeze({
      session_id: 'wsi_expired',
      subject_did: 'did:plc:expired',
      trust_tier: 'self_custody_did',
      scopes: Object.freeze(['forum:read']),
      expires_at: '2026-05-10T01:00:00Z',
    }),
  }),
  challenge: Object.freeze({
    pending: Object.freeze({
      challenge_id: 'wsc_fixture',
      status: 'pending',
      expires_at: '2026-05-11T13:00:00Z',
      deep_link: 'trisaura://web-session/approve?challenge_id=wsc_fixture',
      qr_payload: 'trisaura://web-session/approve?challenge_id=wsc_fixture',
    }),
    approved: Object.freeze({
      challenge_id: 'wsc_fixture',
      status: 'approved',
      trust_tier: 'self_custody_did',
    }),
    rejected: Object.freeze({
      challenge_id: 'wsc_fixture',
      status: 'rejected',
    }),
    expired: Object.freeze({
      challenge_id: 'wsc_fixture',
      status: 'expired',
    }),
  }),
  forum: Object.freeze({
    host: Object.freeze({
      forum_host_id: 'host-local-dev',
      display_name: 'Local Forum Host',
      capabilities: Object.freeze({ create_threads: true }),
    }),
    boards: Object.freeze([
      Object.freeze({
        hosted_board_id: 'general',
        canonical_board_uri: 'http://localhost:4001/boards/general',
        slug: 'general',
        title: 'General',
        description: 'General discussion',
        permissions: Object.freeze({ read: true, write: true }),
      }),
    ]),
    threadAccepted: Object.freeze({
      accepted: true,
      subject_did: 'did:plc:fixture',
      trust_tier: 'self_custody_did',
    }),
  }),
  errors: Object.freeze({
    missingScope: Object.freeze({
      type: ERROR_TYPES.missingScope,
      message: 'Missing required scope: forum:post',
      retryable: false,
      code: 'missing_scope',
      detail: Object.freeze({ requiredScope: 'forum:post' }),
    }),
    rateLimited: Object.freeze({
      type: ERROR_TYPES.rateLimited,
      message: 'rate_limited',
      retryable: true,
      status: 429,
      code: 'rate_limited',
      detail: Object.freeze({ retry_after_seconds: 30 }),
    }),
    boardNotFound: Object.freeze({
      type: ERROR_TYPES.notFound,
      message: 'board_not_found',
      retryable: false,
      code: 'not_found',
      detail: Object.freeze({ boardId: 'missing' }),
    }),
  }),
});

export function createFixtureStorage({ token } = {}) {
  const values = new Map();

  if (token) {
    values.set(WEB_SESSION_TOKEN_KEY, token);
  }

  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, value) {
      values.set(key, String(value));
    },
    removeItem(key) {
      values.delete(key);
    },
  };
}

export function createFixtureWebSessionClient({
  sessionMode = 'approvedDid',
  challengeStatus = 'approved',
} = {}) {
  let approvedByChallenge = false;

  return {
    async createWebSessionChallenge() {
      return CONTRACT_FIXTURES.challenge.pending;
    },
    async fetchChallengeStatus() {
      if (challengeStatus === 'approved') {
        approvedByChallenge = true;
      }

      return CONTRACT_FIXTURES.challenge[challengeStatus];
    },
    async fetchCurrentWebSession({ storage } = {}) {
      if (sessionMode === 'invalid' && approvedByChallenge) {
        return CONTRACT_FIXTURES.sessions.approvedDid;
      }

      if (sessionMode === 'invalid') {
        storage?.removeItem(WEB_SESSION_TOKEN_KEY);
        throw new RelayApiError('invalid_web_session', {
          status: 401,
          code: 'invalid_web_session',
        });
      }

      return CONTRACT_FIXTURES.sessions[sessionMode];
    },
    async revokeWebSession({ storage } = {}) {
      storage?.removeItem(WEB_SESSION_TOKEN_KEY);
      return { revoked: true };
    },
  };
}

export function createFixtureForumHostClient() {
  return {
    async fetchForumHostInfo() {
      return CONTRACT_FIXTURES.forum.host;
    },
    async fetchHostedBoards() {
      return { boards: CONTRACT_FIXTURES.forum.boards };
    },
    async createHostedWebThread() {
      return CONTRACT_FIXTURES.forum.threadAccepted;
    },
  };
}
