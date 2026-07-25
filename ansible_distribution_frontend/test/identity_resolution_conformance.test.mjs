import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import { createForumDataAdapter } from '../src/forum_data_adapter.mjs';
import { renderPageBody } from '../src/forum_page_renderers.mjs';
import { PAGE_IDS } from '../src/state_model.mjs';

const root = new URL('../../contracts/identity-resolution/v1/conformance/', import.meta.url);
const boardCases = JSON.parse(await readFile(new URL('board-resolution.json', root), 'utf8'));
const authorCases = JSON.parse(
  await readFile(new URL('public-author-resolution.json', root), 'utf8'),
);

for (const testCase of boardCases) {
  const board = testCase.boards[0];
  const adapter = createForumDataAdapter({
    relayBaseUrl: 'http://relay.test',
    forumHostClient: {
      async fetchForumHostInfo() {
        return { forum_host_id: 'host-test', display_name: 'Test host' };
      },
      async fetchHostedBoards() {
        return {
          boards: [{
            board_id: Number(board.id),
            hosted_board_id: board.legacy_ids[0] ?? board.slug,
            slug: board.slug,
            title: board.slug,
          }],
        };
      },
      async fetchBoardModerationState() {
        return { removed_posts: [], locked_threads: [] };
      },
    },
    appViewClient: {
      async fetchBoardFeed() {
        return { items: [] };
      },
    },
  });

  const page = await adapter.loadBoardPage({ boardId: testCase.reference });
  if (testCase.expected_id === null) {
    assert.equal(page.error?.type, 'not_found', testCase.name);
  } else {
    assert.equal(page.board?.id ?? null, testCase.expected_id, testCase.name);
  }
}

for (const testCase of authorCases) {
  const author = testCase.author;
  const html = renderPageBody({
    page: { id: PAGE_IDS.thread },
    route: { pageId: PAGE_IDS.thread, params: { boardId: '1', threadId: 'thread-1' } },
    host: { displayName: 'Test host' },
    boards: [{ id: '1', slug: 'fifa2026', title: 'FIFA2026' }],
    board: { id: '1', slug: 'fifa2026', title: 'FIFA2026' },
    thread: {
      id: 'thread-1',
      title: testCase.name,
      authorDid: author.did,
      authorHandle: author.handle,
      posts: [],
    },
    session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
    capabilities: { canCreateThread: false, canReply: false },
  });

  const expectedLabel = testCase.expected === 'anonymous' ? '匿名' : testCase.expected;
  assert.match(html, new RegExp(escapeRegex(expectedLabel)), testCase.name);
}

console.log('frontend identity resolution conformance tests passed');

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
