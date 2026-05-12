import assert from 'node:assert/strict';

import {
  createPageController,
  parseRoute,
  routeToHash,
} from '../src/page_routes.mjs';
import { PAGE_IDS } from '../src/state_model.mjs';
import { DEFAULT_SESSION_VIEW_MODEL } from '../src/session_lifecycle.mjs';

assert.deepEqual(parseRoute(''), { pageId: PAGE_IDS.home, params: {} });
assert.deepEqual(parseRoute('#/'), { pageId: PAGE_IDS.home, params: {} });
assert.deepEqual(parseRoute('#/boards'), { pageId: PAGE_IDS.boards, params: {} });
assert.deepEqual(parseRoute('#/boards/general'), {
  pageId: PAGE_IDS.board,
  params: { boardId: 'general' },
});
assert.deepEqual(parseRoute('#/sessions'), {
  pageId: PAGE_IDS.sessions,
  params: {},
});
assert.deepEqual(parseRoute('#/login'), { pageId: PAGE_IDS.login, params: {} });
assert.deepEqual(parseRoute('#/unknown/path'), {
  pageId: PAGE_IDS.home,
  params: { recoveredFrom: '/unknown/path' },
});
console.log('ok - parses hash routes');

assert.equal(routeToHash({ pageId: PAGE_IDS.home }), '#/');
assert.equal(routeToHash({ pageId: PAGE_IDS.boards }), '#/boards');
assert.equal(routeToHash({ pageId: PAGE_IDS.board, params: { boardId: 'general' } }), '#/boards/general');
assert.equal(routeToHash({ pageId: PAGE_IDS.sessions }), '#/sessions');
assert.equal(routeToHash({ pageId: PAGE_IDS.login }), '#/login');
console.log('ok - serializes route hashes');

const calls = [];
const authenticatedSession = {
  ...DEFAULT_SESSION_VIEW_MODEL,
  authenticated: true,
  mode: 'app_approved_did',
  trustTier: 'self_custody_did',
  capabilities: {
    canRead: true,
    canPost: true,
    canReply: true,
    canRevoke: true,
    canManageProfile: false,
  },
};
const controller = createPageController({
  getCurrentHash: () => '#/boards/general',
  sessionLifecycle: {
    async restore() {
      calls.push('restore');
      return { status: 'authenticated', viewModel: authenticatedSession };
    },
  },
  forumDataAdapter: {
    async loadBoardPage({ boardId, sessionViewModel }) {
      calls.push(['board', boardId, sessionViewModel.trustTier]);
      return {
        host: { id: 'host-local-dev', displayName: 'Local Forum Host' },
        board: { id: boardId, title: 'General' },
        threads: [],
        capabilities: { canCreateThread: true, canReply: true },
        error: null,
      };
    },
  },
});

const boardState = await controller.loadCurrentRoute();
assert.deepEqual(calls, ['restore', ['board', 'general', 'self_custody_did']]);
assert.equal(boardState.route.pageId, PAGE_IDS.board);
assert.equal(boardState.viewModel.page.title, 'General');
assert.equal(boardState.viewModel.actions.canCreateThread, true);
console.log('ok - loads board page skeleton data');

const loginController = createPageController({
  getCurrentHash: () => '#/login',
  sessionLifecycle: {
    async restore() {
      throw new Error('login route should not restore');
    },
  },
  forumDataAdapter: {},
});
const loginState = await loginController.loadCurrentRoute();
assert.equal(loginState.route.pageId, PAGE_IDS.login);
assert.equal(loginState.viewModel.page.title, '登入');
assert.equal(loginState.viewModel.actions.showLogin, true);
console.log('ok - loads login page without data dependencies');
