import assert from 'node:assert/strict';

import {
  PAGE_IDS,
  buildAppViewModel,
  deriveNavigationItems,
  initialAppState,
} from '../src/state_model.mjs';
import { DEFAULT_SESSION_VIEW_MODEL } from '../src/session_lifecycle.mjs';

const appState = initialAppState();
assert.equal(appState.route.pageId, PAGE_IDS.home);
assert.deepEqual(appState.session, DEFAULT_SESSION_VIEW_MODEL);
assert.equal(appState.loading, false);
console.log('ok - creates initial public app state');

const publicHome = buildAppViewModel({
  route: { pageId: PAGE_IDS.home, params: {} },
  session: DEFAULT_SESSION_VIEW_MODEL,
  forum: {
    host: { id: 'host-local-dev', displayName: 'Local Forum Host' },
    boards: [{ id: 'general', title: 'General' }],
    capabilities: { canCreateThread: false },
  },
});
assert.equal(publicHome.page.id, PAGE_IDS.home);
assert.equal(publicHome.page.title, 'Feed');
assert.equal(publicHome.actions.showLogin, true);
assert.equal(publicHome.actions.canCreateThread, false);
assert.equal(publicHome.boards.length, 1);
console.log('ok - builds public home view model');

const authenticatedSession = {
  ...DEFAULT_SESSION_VIEW_MODEL,
  mode: 'app_approved_did',
  authenticated: true,
  trustTier: 'self_custody_did',
  subjectDid: 'did:plc:abc',
  capabilities: {
    canRead: true,
    canPost: true,
    canReply: true,
    canRevoke: true,
    canManageProfile: false,
  },
};
const boardPage = buildAppViewModel({
  route: { pageId: PAGE_IDS.board, params: { boardId: 'general' } },
  session: authenticatedSession,
  forum: {
    host: { id: 'host-local-dev', displayName: 'Local Forum Host' },
    board: { id: 'general', title: 'General' },
    threads: [],
    capabilities: { canCreateThread: true, canReply: true },
  },
});
assert.equal(boardPage.page.id, PAGE_IDS.board);
assert.equal(boardPage.page.title, 'General');
assert.equal(boardPage.actions.showLogin, false);
assert.equal(boardPage.actions.canCreateThread, true);
assert.equal(boardPage.actions.canReply, true);
console.log('ok - builds authenticated board view model');

assert.deepEqual(deriveNavigationItems(DEFAULT_SESSION_VIEW_MODEL), [
  { id: PAGE_IDS.home, label: 'Feed', href: '#/' },
  { id: PAGE_IDS.boards, label: 'Boards', href: '#/boards' },
  { id: PAGE_IDS.login, label: 'Login', href: '#/login' },
]);
assert.deepEqual(deriveNavigationItems(authenticatedSession), [
  { id: PAGE_IDS.home, label: 'Feed', href: '#/' },
  { id: PAGE_IDS.boards, label: 'Boards', href: '#/boards' },
  { id: PAGE_IDS.sessions, label: 'You', href: '#/sessions' },
]);
console.log('ok - derives navigation from session mode');
