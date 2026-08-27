import assert from 'node:assert/strict';

import {
  CONTRACT_FIXTURES,
  createFixtureForumHostClient,
} from '../src/contract_fixtures.mjs';
import {
  buildForumHomeViewModel,
  buildPublicProfileEntries,
  buildThreadsFromFeed,
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
      legacyHostedBoardId: 'general',
      slug: 'general',
      title: 'General',
      description: 'General discussion',
      canonicalUri: 'http://localhost:4001/boards/general',
      permissions: { canRead: true, canWrite: false },
      postingPolicy: { minPostTier: null, externalInclusion: false },
      accessPolicy: {
        version: 1,
        readRequirement: 'public',
        postRequirement: 'posting_policy',
        contentVisibility: 'public',
        federation: 'enabled',
        credentialRequirement: null,
      },
    },
  );
});

test('normalizes dynamic credential posting requirements without Wallet payloads', () => {
  const board = normalizeHostedBoard({
    hosted_board_id: 'members',
    access_policy: {
      version: 1,
      post: { requirement: 'member' },
      content_visibility: 'public',
      federation: 'enabled',
      requirements: {
        member: {
          credential_type: 'MembershipCredential',
          credential_configuration_id: 'board_member',
          trusted_issuers: ['did:web:issuer.example'],
          claims: [
            { path: 'membership', op: 'equals', value: 'member' },
            { path: 'legal_name', op: 'equals', value: 'Must not render' },
          ],
          holder_binding: 'required',
          status: { required: true },
        },
      },
    },
  });

  assert.deepEqual(board.accessPolicy.credentialRequirement, {
    name: 'member',
    credentialType: 'MembershipCredential',
    credentialConfigurationId: 'board_member',
    trustedIssuers: ['did:web:issuer.example'],
    claims: [{ path: 'membership', op: 'equals', value: 'member' }],
    holderBindingRequired: true,
    statusRequired: true,
  });
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
        legacyHostedBoardId: 'general',
        slug: 'general',
        title: 'General',
        description: '',
        canonicalUri: '',
        permissions: { canRead: true, canWrite: true },
        postingPolicy: { minPostTier: null, externalInclusion: false },
        accessPolicy: {
          version: 1,
          readRequirement: 'public',
          postRequirement: 'posting_policy',
          contentVisibility: 'public',
          federation: 'enabled',
          credentialRequirement: null,
        },
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

test('loads and merges anonymous-readable board threads for the public home feed', async () => {
  const feedCalls = [];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    appViewBaseUrl: 'http://localhost:5174',
    forumHostClient: {
      async fetchForumHostInfo() {
        return { forum_host_id: 'host', display_name: 'Host' };
      },
      async fetchHostedBoards() {
        return {
          boards: [
            {
              board_id: 1,
              hosted_board_id: 'public',
              slug: 'public',
              title: 'Public',
              permissions: { read: true },
              access_policy: {
                content_visibility: 'public',
                read: { requirement: 'public' },
              },
            },
            {
              board_id: 2,
              hosted_board_id: 'members',
              permissions: { read: true },
              access_policy: {
                content_visibility: 'restricted',
                read: { requirement: 'member' },
              },
            },
          ],
        };
      },
    },
    appViewClient: {
      async fetchBoardFeed({ boardId }) {
        feedCalls.push(boardId);
        return {
          items: [
            {
              entity_type: 'thread',
              op_type: 'insert',
              entity_id: 'thread-1',
              board_id: 'legacy_public',
              author_did: 'did:elix:author',
              created_at: '2026-08-23T01:00:00Z',
              payload: { title: 'Anonymous readers can see this' },
            },
          ],
        };
      },
    },
  });

  const home = await adapter.loadForumHome({
    sessionViewModel: { authenticated: false },
    includePublicFeed: true,
  });

  assert.deepEqual(feedCalls, ['1']);
  assert.equal(home.publicFeed.unavailable, false);
  assert.equal(home.publicFeed.threads.length, 1);
  assert.equal(home.publicFeed.threads[0].boardId, '1');
  assert.equal(home.publicFeed.threads[0].boardSlug, 'public');
  assert.equal(home.publicFeed.threads[0].title, 'Anonymous readers can see this');
});

test('loads only explicit public profile fields and public author posts', async () => {
  const calls = [];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    appViewBaseUrl: 'http://localhost:5174',
    forumHostClient: {
      async fetchForumHostInfo() {
        return { forum_host_id: 'host', display_name: 'Host' };
      },
      async fetchHostedBoards() {
        return { boards: [] };
      },
    },
    appViewClient: {
      async fetchPublicProfile({ did }) {
        calls.push(['profile', did]);
        return {
          did,
          handle: 'mira.elix.cool',
          display_name: 'Mira',
          bio: 'Writing slowly.',
          reputation_tier: 'verified_human',
        };
      },
      async fetchAuthorTimeline({ did, limit }) {
        calls.push(['timeline', did, limit]);
        return {
          items: [
            {
              entity_type: 'note',
              entity_id: 'note-1',
              author_did: did,
              visibility: 'public',
              created_at: '2026-08-27T04:00:00Z',
              payload: { title: 'Public note', body: 'Visible body' },
            },
            {
              entity_type: 'note',
              entity_id: 'note-hidden',
              author_did: did,
              visibility: 'unlisted',
              payload: { body: 'Must stay hidden' },
            },
          ],
        };
      },
    },
  });

  const page = await adapter.loadProfilePage({
    did: 'did:elix:mira',
    sessionViewModel: { authenticated: false },
  });

  assert.deepEqual(calls, [
    ['profile', 'did:elix:mira'],
    ['timeline', 'did:elix:mira', 100],
  ]);
  assert.equal(page.profile.displayName, 'Mira');
  assert.equal(page.profile.bio, 'Writing slowly.');
  assert.equal(page.profile.reputationTier, 'verified_human');
  assert.equal(page.profilePosts.length, 1);
  assert.equal(page.profilePosts[0].title, 'Public note');
});

test('deduplicates a public discussion thread and excludes replies', () => {
  const entries = buildPublicProfileEntries([
    {
      entity_type: 'thread',
      entity_id: 'thread-1',
      board_id: 'general',
      visibility: 'public',
      payload: { title: 'Thread title', description: 'Thread description' },
    },
    {
      entity_type: 'post',
      entity_id: 'post-1',
      thread_id: 'thread-1',
      board_id: 'general',
      visibility: 'public',
      payload: { content: 'Opening post' },
    },
    {
      entity_type: 'post',
      entity_id: 'reply-1',
      thread_id: 'thread-1',
      board_id: 'general',
      visibility: 'public',
      payload: { parentPostId: 'post-1', content: 'Reply' },
    },
  ]);

  assert.equal(entries.length, 1);
  assert.equal(entries[0].id, 'post-1');
  assert.equal(entries[0].title, 'Thread title');
  assert.equal(entries[0].body, 'Opening post');
});

test('reports a degraded public home feed instead of confusing failure with no posts', async () => {
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      async fetchForumHostInfo() {
        return {};
      },
      async fetchHostedBoards() {
        return {
          boards: [{ hosted_board_id: 'general', permissions: { read: true } }],
        };
      },
    },
    appViewClient: {
      async fetchBoardFeed() {
        throw new Error('appview unavailable');
      },
    },
  });

  const home = await adapter.loadForumHome({ includePublicFeed: true });
  assert.deepEqual(home.publicFeed, { threads: [], unavailable: true });
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

test('loads thread detail from the AppView thread feed', async () => {
  const calls = [];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    appViewBaseUrl: 'http://localhost:5174',
    forumHostClient: {
      async fetchForumHostInfo() {
        calls.push(['host']);
        return {
          forum_host_id: 'host-local-dev',
          display_name: 'Local Forum Host',
          capabilities: { create_threads: true },
        };
      },
      async fetchHostedBoards() {
        calls.push(['boards']);
        return {
          boards: [
            {
              board_id: 1,
              hosted_board_id: 'fifa2026',
              slug: 'fifa2026',
              title: 'FIFA2026',
            },
          ],
        };
      },
      async fetchBoardModerationState({ boardId }) {
        calls.push(['moderation', boardId]);
        return { removed_posts: [], locked_threads: [] };
      },
    },
    appViewClient: {
      async fetchThreadFeed({ appViewBaseUrl, threadId }) {
        calls.push(['thread-feed', appViewBaseUrl, threadId]);
        return {
          items: [
            {
              entity_type: 'thread',
              op_type: 'insert',
              entity_id: 'thread-9',
              author_did: 'did:plc:author',
              created_at: '2026-06-18T14:33:27.083198Z',
              payload: { title: '不見了', threadId: 'thread-9' },
            },
            {
              entity_type: 'post',
              op_type: 'insert',
              entity_id: 'post-1',
              author_did: 'did:plc:author',
              created_at: '2026-06-18T14:33:27.093554Z',
              payload: { threadId: 'thread-9', content: '文章不見了？！' },
            },
          ],
        };
      },
    },
  });

  const page = await adapter.loadThreadPage({
    boardId: 'fifa2026',
    threadId: 'thread-9',
    sessionViewModel: AUTHENTICATED_SESSION,
  });

  assert.equal(page.board.id, '1');
  assert.equal(page.board.slug, 'fifa2026');
  assert.equal(page.thread.id, 'thread-9');
  assert.equal(page.thread.title, '不見了');
  assert.equal(page.thread.posts[0].content, '文章不見了？！');
  assert.deepEqual(calls, [
    ['host'],
    ['boards'],
    ['moderation', '1'],
    ['thread-feed', 'http://localhost:5174', 'thread-9'],
  ]);
});

test('marks missing thread detail routes with a semantic error', async () => {
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: {
      async fetchForumHostInfo() {
        return { forum_host_id: 'host-local-dev', display_name: 'Local Forum Host' };
      },
      async fetchHostedBoards() {
        return { boards: [{ hosted_board_id: 'fifa2026', slug: 'fifa2026', title: 'FIFA2026' }] };
      },
      async fetchBoardModerationState() {
        return { removed_posts: [], locked_threads: [] };
      },
    },
    appViewClient: {
      async fetchThreadFeed() {
        return { items: [] };
      },
    },
  });

  const page = await adapter.loadThreadPage({ boardId: 'fifa2026', threadId: 'missing' });
  assert.equal(page.thread, null);
  assert.equal(page.error.type, ERROR_TYPES.notFound);
});

test('normalizes AppView post content into thread posts', () => {
  const [thread] = buildThreadsFromFeed([
    {
      entity_type: 'thread',
      op_type: 'insert',
      entity_id: 'thread-9',
      author_did: 'did:plc:thread-author',
      author_display_name: 'Thread Author',
      author_handle: 'thread-author.elix.cool',
      board_id: 'general',
      created_at: '2026-06-18T14:33:27.083198Z',
      payload: { title: '不見了' },
    },
    {
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'post-1',
      author_did: 'did:plc:reply-author',
      author_display_name: 'Reply Author',
      author_handle: 'reply-author.elix.cool',
      created_at: '2026-06-18T14:33:27.093554Z',
      payload: { threadId: 'thread-9', content: '文章不見了？！' },
    },
  ]);

  assert.equal(thread.authorHandle, 'thread-author.elix.cool');
  assert.equal(thread.authorDisplayName, 'Thread Author');
  assert.equal(thread.boardId, 'general');
  assert.equal(thread.posts[0].authorHandle, 'reply-author.elix.cool');
  assert.equal(thread.posts[0].authorDisplayName, 'Reply Author');
  assert.equal(thread.posts[0].content, '文章不見了？！');
});

test('falls back to the Relay-registered handle when AppView has no profile op', async () => {
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'https://relay.example',
    fetchImpl: async (url) => {
      assert.equal(
        url,
        'https://relay.example/api/v1/identity/handle/did%3Aelix%3Amashbean',
      );
      return new Response(JSON.stringify({ handle: 'mashbean.elix.cool' }), { status: 200 });
    },
    forumHostClient: {
      async fetchForumHostInfo() {
        return { forum_host_id: 'host', display_name: 'Host' };
      },
      async fetchHostedBoards() {
        return { boards: [{ hosted_board_id: 'general', slug: 'general', title: 'General' }] };
      },
      async fetchBoardModerationState() {
        return {};
      },
    },
    appViewClient: {
      async fetchThreadFeed() {
        return {
          items: [{
            entity_type: 'thread',
            op_type: 'insert',
            entity_id: 'thread-1',
            author_did: 'did:elix:mashbean',
            board_id: 'general',
            created_at: '2026-08-23T12:39:00Z',
            payload: { title: 'Handle fallback' },
          }],
        };
      },
    },
  });

  const page = await adapter.loadThreadPage({ boardId: 'general', threadId: 'thread-1' });
  assert.equal(page.thread.authorHandle, 'mashbean.elix.cool');
  assert.equal(page.thread.authorDisplayName, null);
});

test('projects signed thread/post updates and deletes from the schema feed', () => {
  const threads = buildThreadsFromFeed([
    {
      log_id: 1,
      op_id: 'thread-insert',
      entity_type: 'thread',
      op_type: 'insert',
      entity_id: 'thread-1',
      author_did: 'did:elix:alice',
      board_id: 'general',
      created_at: '2026-07-25T01:00:00Z',
      payload: { title: 'Original' },
    },
    {
      log_id: 2,
      op_id: 'post-insert',
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'post-1',
      author_did: 'did:elix:alice',
      created_at: '2026-07-25T01:01:00Z',
      payload: { threadId: 'thread-1', content: 'Original body' },
    },
    {
      log_id: 3,
      op_id: 'thread-update',
      entity_type: 'thread',
      op_type: 'update',
      entity_id: 'thread-1',
      author_did: 'did:elix:alice',
      created_at: '2026-07-25T01:02:00Z',
      payload: { title: 'Edited' },
    },
    {
      log_id: 4,
      op_id: 'post-update',
      entity_type: 'post',
      op_type: 'update',
      entity_id: 'post-1',
      author_did: 'did:elix:alice',
      created_at: '2026-07-25T01:03:00Z',
      payload: { content: 'Edited body' },
    },
  ]);

  assert.equal(threads[0].title, 'Edited');
  assert.equal(threads[0].revision, 'thread-update');
  assert.equal(threads[0].posts[0].content, 'Edited body');
  assert.equal(threads[0].posts[0].revision, 'post-update');

  assert.deepEqual(buildThreadsFromFeed([
    {
      op_id: 'thread-insert',
      entity_type: 'thread',
      op_type: 'insert',
      entity_id: 'thread-1',
      author_did: 'did:elix:alice',
      payload: { title: 'Original' },
    },
    {
      op_id: 'thread-delete',
      entity_type: 'thread',
      op_type: 'delete',
      entity_id: 'thread-1',
      author_did: 'did:elix:alice',
      payload: { deletedAt: '2026-07-25T01:04:00Z' },
    },
  ]), []);
});

test('projects active reactions into thread and reply counts without double-counting updates', () => {
  const [thread] = buildThreadsFromFeed([
    {
      log_id: 1,
      entity_type: 'thread',
      op_type: 'insert',
      entity_id: 'thread-1',
      payload: { title: 'Reaction target' },
    },
    {
      log_id: 2,
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'post-1',
      payload: { threadId: 'thread-1', content: 'Reply target' },
    },
    {
      log_id: 3,
      entity_type: 'reaction',
      op_type: 'insert',
      entity_id: 'reaction-a',
      payload: { targetType: 'thread', targetId: 'thread-1', reactionType: 'thumbsUp' },
    },
    {
      log_id: 4,
      entity_type: 'reaction',
      op_type: 'update',
      entity_id: 'reaction-a',
      payload: { targetType: 'thread', targetId: 'thread-1', reactionType: 'happy' },
    },
    {
      log_id: 5,
      entity_type: 'reaction',
      op_type: 'insert',
      entity_id: 'reaction-b',
      payload: { targetType: 'post', targetId: 'post-1', reactionType: 'happy' },
    },
    {
      log_id: 6,
      entity_type: 'reaction',
      op_type: 'delete',
      entity_id: 'reaction-b',
      payload: { targetType: 'post', targetId: 'post-1' },
    },
  ]);

  assert.equal(thread.likeCount, 1);
  assert.equal(thread.posts[0].likeCount ?? 0, 0);
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
    boardId: 'general',
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
  assert.equal(submissions[0].boardId, 'general');

  await assert.rejects(
    () =>
      adapter.submitThreadDraft({
        title: 'Blocked',
        boardId: 'general',
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
