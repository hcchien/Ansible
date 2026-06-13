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
    gatedBoard: Object.freeze({
      hosted_board_id: 'verified-humans',
      canonical_board_uri: 'http://localhost:4001/boards/verified-humans',
      slug: 'verified-humans',
      title: 'Verified Humans',
      description: 'Only verified humans can post here',
      permissions: Object.freeze({ read: true, write: true }),
      posting_policy: Object.freeze({ min_post_tier: 'verified_human' }),
    }),
    externalBoard: Object.freeze({
      hosted_board_id: 'fediverse-watch',
      canonical_board_uri: 'http://localhost:4001/boards/fediverse-watch',
      slug: 'fediverse-watch',
      title: 'Fediverse Watch',
      description: 'Includes curated content from the wider fediverse',
      permissions: Object.freeze({ read: true, write: true }),
      posting_policy: Object.freeze({ external_inclusion: true }),
    }),
    threadAccepted: Object.freeze({
      accepted: true,
      subject_did: 'did:plc:fixture',
      trust_tier: 'self_custody_did',
    }),
    // AppView GET /api/v1/boards/:id/external response shape (the committed
    // contract). External items are never-verified, carry a fixed
    // external_unverified tier, a visible origin, and a compliance level.
    externalResponse: Object.freeze({
      items: Object.freeze([
        Object.freeze({
          log_id: 'log-ext-1',
          op_id: 'op-ext-1',
          board_id: 'fediverse-watch',
          content: 'Hello from the fediverse <script>alert(1)</script>',
          created_at: '2026-06-13T03:00:00Z',
          external_actor_uri: 'https://g0v.social/users/alice',
          external_instance: 'g0v.social',
          compliance_level: 'compatible',
          reputation_tier: 'external_unverified',
          external: true,
          origin: 'activitypub',
        }),
        Object.freeze({
          log_id: 'log-ext-2',
          op_id: 'op-ext-2',
          board_id: 'fediverse-watch',
          content: 'A post from an un-assessed instance',
          created_at: '2026-06-13T03:05:00Z',
          external_actor_uri: 'https://example.social/users/bob',
          external_instance: 'example.social',
          compliance_level: 'unknown',
          reputation_tier: 'external_unverified',
          external: true,
          origin: 'activitypub',
        }),
      ]),
      next_cursor: null,
      has_more: false,
    }),
  }),
  moderation: Object.freeze({
    report: Object.freeze({
      id: 41,
      target_kind: 'post',
      target_ref: 'post-201',
      board_id: 'general',
      reporter_did: 'did:plc:reporter',
      reason_code: 'spam',
      note: null,
      status: 'open',
      inserted_at: '2026-06-13T01:00:00Z',
    }),
    openReports: Object.freeze([
      Object.freeze({
        id: 41,
        target_kind: 'post',
        target_ref: 'post-201',
        board_id: 'general',
        reporter_did: 'did:plc:reporter',
        reason_code: 'spam',
        note: null,
        status: 'open',
        inserted_at: '2026-06-13T01:00:00Z',
      }),
      Object.freeze({
        id: 42,
        target_kind: 'thread',
        target_ref: 'thread-9',
        board_id: 'general',
        reporter_did: 'did:plc:reporter',
        reason_code: 'harassment',
        note: null,
        status: 'open',
        inserted_at: '2026-06-13T01:05:00Z',
      }),
      Object.freeze({
        id: 43,
        target_kind: 'post',
        target_ref: 'post-300',
        board_id: 'verified-humans',
        reporter_did: 'did:plc:other-reporter',
        reason_code: 'other',
        note: '冒充板主發言',
        status: 'open',
        inserted_at: '2026-06-13T01:10:00Z',
      }),
    ]),
    auditActions: Object.freeze([
      Object.freeze({
        id: 7,
        action: 'remove_post_from_board',
        target_ref: 'post-101',
        board_id: 'general',
        moderator_did: 'did:plc:fixture',
        reason_code: 'spam',
        report_id: 40,
        inserted_at: '2026-06-12T09:00:00Z',
      }),
    ]),
    actionAccepted: Object.freeze({
      id: 8,
      action: 'lock_thread',
      target_ref: 'thread-9',
      board_id: 'general',
      moderator_did: 'did:plc:fixture',
      reason_code: 'harassment',
      report_id: 42,
      inserted_at: '2026-06-13T02:00:00Z',
    }),
    boardState: Object.freeze({
      removed_posts: Object.freeze([
        Object.freeze({ target_ref: 'post-101', reason_code: 'spam' }),
      ]),
      locked_threads: Object.freeze([
        Object.freeze({ thread_id: 'thread-9', reason_code: 'harassment' }),
      ]),
    }),
    emptyBoardState: Object.freeze({
      removed_posts: Object.freeze([]),
      locked_threads: Object.freeze([]),
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
    postingRequiresTier: Object.freeze({
      type: ERROR_TYPES.postingRequiresTier,
      message: 'posting_requires_tier',
      retryable: false,
      status: 403,
      code: 'posting_requires_tier',
      detail: Object.freeze({
        requiredTier: 'verified_human',
        currentTier: 'basic',
      }),
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
    notBoardModerator: Object.freeze({
      type: ERROR_TYPES.notBoardModerator,
      message: 'not_board_moderator',
      retryable: false,
      status: 403,
      code: 'not_board_moderator',
      detail: undefined,
    }),
    invalidReasonCode: Object.freeze({
      type: ERROR_TYPES.invalidRequest,
      message: 'invalid_reason_code',
      retryable: false,
      status: 422,
      code: 'invalid_reason_code',
      detail: undefined,
    }),
    unknownTarget: Object.freeze({
      type: ERROR_TYPES.invalidRequest,
      message: 'unknown_target',
      retryable: false,
      status: 422,
      code: 'unknown_target',
      detail: undefined,
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

export function createFixtureForumHostClient({
  moderator = true,
  reportOutcome = 'created',
  includeExternalBoard = false,
} = {}) {
  return {
    async fetchForumHostInfo() {
      return CONTRACT_FIXTURES.forum.host;
    },
    async fetchHostedBoards() {
      const boards = includeExternalBoard
        ? [...CONTRACT_FIXTURES.forum.boards, CONTRACT_FIXTURES.forum.externalBoard]
        : CONTRACT_FIXTURES.forum.boards;
      return { boards };
    },
    async createHostedWebThread() {
      return CONTRACT_FIXTURES.forum.threadAccepted;
    },
    async submitWebReport() {
      if (reportOutcome === 'rate_limited') {
        throw new RelayApiError('rate_limited', { status: 429, code: 'rate_limited' });
      }

      if (reportOutcome === 'invalid_reason') {
        throw new RelayApiError('invalid_reason_code', {
          status: 422,
          code: 'invalid_reason_code',
        });
      }

      if (reportOutcome === 'unknown_target') {
        throw new RelayApiError('unknown_target', {
          status: 422,
          code: 'unknown_target',
        });
      }

      return {
        report: CONTRACT_FIXTURES.moderation.report,
        duplicate: reportOutcome === 'duplicate',
      };
    },
    async fetchWebModerationReports() {
      assertModerator(moderator);
      return { reports: CONTRACT_FIXTURES.moderation.openReports };
    },
    async fetchWebModerationActions() {
      assertModerator(moderator);
      return { actions: CONTRACT_FIXTURES.moderation.auditActions };
    },
    async submitWebModerationAction({ action, targetRef, boardId, reasonCode, reportId }) {
      assertModerator(moderator);
      return {
        action: {
          ...CONTRACT_FIXTURES.moderation.actionAccepted,
          action,
          target_ref: targetRef,
          board_id: boardId,
          reason_code: reasonCode,
          report_id: reportId ?? null,
        },
      };
    },
    async fetchBoardModerationState({ boardId } = {}) {
      return boardId === 'general'
        ? CONTRACT_FIXTURES.moderation.boardState
        : CONTRACT_FIXTURES.moderation.emptyBoardState;
    },
  };
}

function assertModerator(moderator) {
  if (!moderator) {
    throw new RelayApiError('not_board_moderator', {
      status: 403,
      code: 'not_board_moderator',
    });
  }
}

// Fixture AppView client for the curated external-content read path.
// outcome: 'ok' returns the committed external response; 'unavailable' throws
// (simulating an AppView outage); 'empty' returns no items.
export function createFixtureAppViewClient({ outcome = 'ok' } = {}) {
  return {
    async fetchBoardExternalContent({ boardId } = {}) {
      if (outcome === 'unavailable') {
        throw new RelayApiError('appview_unavailable', {
          status: 502,
          code: 'appview_unavailable',
        });
      }

      if (outcome === 'empty') {
        return { items: [], next_cursor: null, has_more: false };
      }

      return {
        ...CONTRACT_FIXTURES.forum.externalResponse,
        items: CONTRACT_FIXTURES.forum.externalResponse.items.map((item) => ({
          ...item,
          board_id: boardId ?? item.board_id,
        })),
      };
    },
  };
}
