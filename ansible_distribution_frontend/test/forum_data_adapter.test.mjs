import assert from 'node:assert/strict';

import {
  CONTRACT_FIXTURES,
  createFixtureForumHostClient,
} from '../src/contract_fixtures.mjs';
import {
  buildForumHomeViewModel,
  createForumDataAdapter,
  normalizeHostedBoard,
} from '../src/forum_data_adapter.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';

const AUTHENTICATED_SESSION = {
  authenticated: true,
  trustTier: 'self_custody_did',
  subjectDid: 'did:plc:fixture',
  capabilities: { canPost: true, canReply: true },
};

function fixtureAdapter(clientOptions = {}) {
  return createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: createFixtureForumHostClient(clientOptions),
  });
}

const tests = [];

function test(name, body) {
  tests.push({ name, body });
}

test('normalizes hosted boards into UI-ready board records', () => {
  assert.deepEqual(
    normalizeHostedBoard({
      hosted_board_id: 'general',
      canonical_board_uri: 'http://localhost:4001/boards/general',
      slug: 'general',
      title: 'General',
      description: 'General discussion',
      permissions: { read: true, write: false },
    }),
    {
      id: 'general',
      slug: 'general',
      title: 'General',
      description: 'General discussion',
      canonicalUri: 'http://localhost:4001/boards/general',
      permissions: { canRead: true, canWrite: false },
      postingPolicy: { minPostTier: null, externalInclusion: false },
    },
  );
});

test('normalizes the posting policy gate on tier-gated boards', () => {
  const gated = normalizeHostedBoard({
    hosted_board_id: 'verified-humans',
    slug: 'verified-humans',
    title: 'Verified Humans',
    posting_policy: { min_post_tier: 'verified_human' },
  });

  assert.deepEqual(gated.postingPolicy, {
    minPostTier: 'verified_human',
    externalInclusion: false,
  });
});

test('builds forum home data from host, boards, and session capabilities', () => {
  const home = buildForumHomeViewModel({
    host: {
      forum_host_id: 'host-local-dev',
      display_name: 'Local Forum Host',
      capabilities: { create_threads: true },
    },
    boards: [
      {
        hosted_board_id: 'general',
        slug: 'general',
        title: 'General',
        permissions: { read: true, write: true },
      },
    ],
    sessionViewModel: {
      capabilities: { canPost: true, canReply: false },
      trustTier: 'self_custody_did',
    },
  });

  assert.deepEqual(home, {
    host: {
      id: 'host-local-dev',
      displayName: 'Local Forum Host',
      capabilities: { createThreads: true },
    },
    boards: [
      {
        id: 'general',
        slug: 'general',
        title: 'General',
        description: '',
        canonicalUri: '',
        permissions: { canRead: true, canWrite: true },
        postingPolicy: { minPostTier: null, externalInclusion: false },
      },
    ],
    primaryBoardId: 'general',
    capabilities: {
      canCreateThread: true,
      canReply: false,
    },
    trustTier: 'self_custody_did',
  });
});

test('loads forum home data through the Forum Host client', async () => {
  const calls = [];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      async fetchForumHostInfo(params) {
        calls.push(['host', params.relayBaseUrl]);
        return {
          forum_host_id: 'host-local-dev',
          display_name: 'Local Forum Host',
          capabilities: { create_threads: true },
        };
      },
      async fetchHostedBoards(params) {
        calls.push(['boards', params.relayBaseUrl]);
        return {
          boards: [{ hosted_board_id: 'general', title: 'General' }],
        };
      },
    },
  });

  const home = await adapter.loadForumHome({
    sessionViewModel: {
      trustTier: 'anonymous',
      capabilities: { canPost: false, canReply: false },
    },
  });

  assert.deepEqual(calls, [
    ['host', 'http://localhost:4001'],
    ['boards', 'http://localhost:4001'],
  ]);
  assert.equal(home.primaryBoardId, 'general');
  assert.equal(home.capabilities.canCreateThread, false);
});

test('loads board data and marks missing boards with a semantic error', async () => {
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      async fetchForumHostInfo() {
        return {
          forum_host_id: 'host-local-dev',
          display_name: 'Local Forum Host',
          capabilities: { create_threads: true },
        };
      },
      async fetchHostedBoards() {
        return {
          boards: [{ hosted_board_id: 'general', title: 'General' }],
        };
      },
    },
  });

  const existing = await adapter.loadBoardPage({ boardId: 'general' });
  assert.equal(existing.board.id, 'general');
  assert.deepEqual(existing.threads, []);

  const missing = await adapter.loadBoardPage({ boardId: 'missing' });
  assert.equal(missing.error.type, ERROR_TYPES.notFound);
  assert.equal(missing.board.id, 'missing');
  assert.equal(missing.board.missing, true);
});

test('submits thread drafts only when the session can post', async () => {
  const submissions = [];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    storage: { getItem: () => 'wst_test' },
    forumHostClient: {
      async createHostedWebThread(params) {
        submissions.push(params);
        return {
          accepted: true,
          subject_did: 'did:plc:abc',
          trust_tier: 'self_custody_did',
        };
      },
    },
  });

  const accepted = await adapter.submitThreadDraft({
    title: 'Hello Forum',
    sessionViewModel: {
      capabilities: { canPost: true },
    },
  });

  assert.deepEqual(accepted, {
    accepted: true,
    subjectDid: 'did:plc:abc',
    trustTier: 'self_custody_did',
  });
  assert.equal(submissions[0].title, 'Hello Forum');

  await assert.rejects(
    () =>
      adapter.submitThreadDraft({
        title: 'Blocked',
        sessionViewModel: {
          capabilities: { canPost: false },
        },
      }),
    (error) => {
      assert.equal(error.type, ERROR_TYPES.missingScope);
      assert.equal(error.detail.requiredScope, 'forum:post');
      return true;
    },
  );
});

test('submits a report and reports created vs duplicate-collapsed outcomes', async () => {
  const created = await fixtureAdapter().submitReport({
    targetKind: 'post',
    targetRef: 'post-201',
    boardId: 'general',
    reasonCode: 'spam',
    sessionViewModel: AUTHENTICATED_SESSION,
  });
  assert.equal(created.duplicate, false);
  assert.equal(created.report.id, 41);
  assert.equal(created.report.reasonCode, 'spam');
  assert.equal(created.report.status, 'open');

  const duplicate = await fixtureAdapter({ reportOutcome: 'duplicate' }).submitReport({
    targetKind: 'post',
    targetRef: 'post-201',
    boardId: 'general',
    reasonCode: 'spam',
    sessionViewModel: AUTHENTICATED_SESSION,
  });
  assert.equal(duplicate.duplicate, true);
});

test('propagates relay report rejections (429 rate limit, 422 invalid/unknown)', async () => {
  const submit = (adapter) =>
    adapter.submitReport({
      targetKind: 'post',
      targetRef: 'post-201',
      boardId: 'general',
      reasonCode: 'spam',
      sessionViewModel: AUTHENTICATED_SESSION,
    });

  await assert.rejects(
    () => submit(fixtureAdapter({ reportOutcome: 'rate_limited' })),
    (error) => {
      assert.equal(error.status, 429);
      assert.equal(error.code, 'rate_limited');
      return true;
    },
  );

  await assert.rejects(
    () => submit(fixtureAdapter({ reportOutcome: 'invalid_reason' })),
    (error) => {
      assert.equal(error.status, 422);
      assert.equal(error.code, 'invalid_reason_code');
      return true;
    },
  );

  await assert.rejects(
    () => submit(fixtureAdapter({ reportOutcome: 'unknown_target' })),
    (error) => {
      assert.equal(error.status, 422);
      assert.equal(error.code, 'unknown_target');
      return true;
    },
  );
});

test('requires a note before submitting an "other" report and a session first', async () => {
  let relayCalled = false;
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      async submitWebReport() {
        relayCalled = true;
        return { report: CONTRACT_FIXTURES.moderation.report, duplicate: false };
      },
    },
  });

  await assert.rejects(
    () =>
      adapter.submitReport({
        targetKind: 'post',
        targetRef: 'post-201',
        boardId: 'general',
        reasonCode: 'other',
        note: '  ',
        sessionViewModel: AUTHENTICATED_SESSION,
      }),
    (error) => {
      assert.equal(error.type, ERROR_TYPES.invalidRequest);
      assert.equal(error.code, 'note_required');
      return true;
    },
  );

  await assert.rejects(
    () =>
      adapter.submitReport({
        targetKind: 'post',
        targetRef: 'post-201',
        boardId: 'general',
        reasonCode: 'spam',
        sessionViewModel: { authenticated: false },
      }),
    (error) => {
      assert.equal(error.type, ERROR_TYPES.unauthenticated);
      return true;
    },
  );

  assert.equal(relayCalled, false);
});

test('loads the moderation console queue grouped by board with the audit trail', async () => {
  const { moderation } = await fixtureAdapter().loadModerationConsole({
    sessionViewModel: AUTHENTICATED_SESSION,
  });

  assert.equal(moderation.status, 'moderator');
  assert.equal(moderation.error, null);
  assert.deepEqual(
    moderation.reportGroups.map((group) => [
      group.boardId,
      group.reports.map((report) => report.id),
    ]),
    [
      ['general', [41, 42]],
      ['verified-humans', [43]],
    ],
  );
  assert.equal(moderation.reportGroups[1].reports[0].note, '冒充板主發言');
  assert.deepEqual(moderation.auditActions, [
    {
      id: 7,
      action: 'remove_post_from_board',
      targetRef: 'post-101',
      boardId: 'general',
      moderatorDid: 'did:plc:fixture',
      reasonCode: 'spam',
      reportId: 40,
      insertedAt: '2026-06-12T09:00:00Z',
    },
  ]);
});

test('maps the relay 403 to a not-moderator console state instead of throwing', async () => {
  const { moderation } = await fixtureAdapter({ moderator: false }).loadModerationConsole({
    sessionViewModel: AUTHENTICATED_SESSION,
  });

  assert.equal(moderation.status, 'not_moderator');
  assert.deepEqual(moderation.reportGroups, []);
  assert.deepEqual(moderation.auditActions, []);
  assert.equal(moderation.error.type, ERROR_TYPES.notBoardModerator);
  assert.equal(moderation.error.status, 403);
});

test('returns a signed-out console state without calling the relay', async () => {
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      async fetchWebModerationReports() {
        throw new Error('must not be called while signed out');
      },
      async fetchWebModerationActions() {
        throw new Error('must not be called while signed out');
      },
    },
  });

  const { moderation } = await adapter.loadModerationConsole({
    sessionViewModel: { authenticated: false },
  });
  assert.equal(moderation.status, 'signed_out');
});

test('submits each moderation action over the web session rail', async () => {
  const calls = [];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      ...createFixtureForumHostClient(),
      async submitWebModerationAction(params) {
        calls.push(params);
        return {
          action: {
            ...CONTRACT_FIXTURES.moderation.actionAccepted,
            action: params.action,
            target_ref: params.targetRef,
            board_id: params.boardId,
            reason_code: params.reasonCode,
            report_id: params.reportId,
          },
        };
      },
    },
  });

  const cases = [
    { action: 'dismiss_report', targetRef: 'post-201', reportId: 41 },
    { action: 'remove_post_from_board', targetRef: 'post-201', reportId: 41 },
    { action: 'lock_thread', targetRef: 'thread-9', reportId: 42 },
    { action: 'unlock_thread', targetRef: 'thread-9', reportId: null },
  ];

  for (const item of cases) {
    const recorded = await adapter.submitModerationAction({
      ...item,
      boardId: 'general',
      reasonCode: 'spam',
    });
    assert.equal(recorded.action, item.action);
    assert.equal(recorded.targetRef, item.targetRef);
    assert.equal(recorded.boardId, 'general');
    assert.equal(recorded.reasonCode, 'spam');
    assert.equal(recorded.reportId, item.reportId);
  }

  assert.deepEqual(
    calls.map((call) => [call.action, call.targetRef, call.reportId]),
    cases.map((item) => [item.action, item.targetRef, item.reportId]),
  );
});

test('loads the public board moderation state alongside the board page', async () => {
  const page = await fixtureAdapter().loadBoardPage({ boardId: 'general' });

  assert.deepEqual(page.moderationState, {
    removedPosts: [{ targetRef: 'post-101', reasonCode: 'spam' }],
    lockedThreads: [{ threadId: 'thread-9', reasonCode: 'harassment' }],
  });
});

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
