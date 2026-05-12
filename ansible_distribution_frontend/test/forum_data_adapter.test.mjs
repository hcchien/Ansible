import assert from 'node:assert/strict';

import {
  buildForumHomeViewModel,
  createForumDataAdapter,
  normalizeHostedBoard,
} from '../src/forum_data_adapter.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';

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
    },
  );
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

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
