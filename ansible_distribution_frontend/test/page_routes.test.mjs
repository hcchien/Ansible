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
assert.equal(PAGE_IDS.thread, 'thread');
assert.deepEqual(parseRoute('#/boards/general/threads/thread-9'), {
  pageId: PAGE_IDS.thread,
  params: { boardId: 'general', threadId: 'thread-9' },
});
assert.deepEqual(parseRoute('#/boards/general/deliberations/deliberation-9'), {
  pageId: PAGE_IDS.deliberation,
  params: { boardId: 'general', deliberationId: 'deliberation-9' },
});
assert.deepEqual(parseRoute('#/profiles/did%3Aelix%3Amira'), {
  pageId: PAGE_IDS.profile,
  params: { did: 'did:elix:mira' },
});
assert.deepEqual(parseRoute('#/sessions'), {
  pageId: PAGE_IDS.sessions,
  params: {},
});
assert.deepEqual(parseRoute('#/notifications'), {
  pageId: PAGE_IDS.notifications,
  params: {},
});
assert.deepEqual(parseRoute('#/login'), { pageId: PAGE_IDS.login, params: {} });
assert.deepEqual(parseRoute('#/moderation'), {
  pageId: PAGE_IDS.moderation,
  params: {},
});
assert.deepEqual(parseRoute('#/about'), { pageId: PAGE_IDS.faq, params: {} });
assert.deepEqual(parseRoute('#/unknown/path'), {
  pageId: PAGE_IDS.home,
  params: { recoveredFrom: '/unknown/path' },
});
console.log('ok - parses hash routes');

assert.equal(routeToHash({ pageId: PAGE_IDS.home }), '#/');
assert.equal(routeToHash({ pageId: PAGE_IDS.boards }), '#/boards');
assert.equal(routeToHash({ pageId: PAGE_IDS.board, params: { boardId: 'general' } }), '#/boards/general');
assert.equal(
  routeToHash({ pageId: PAGE_IDS.thread, params: { boardId: 'general', threadId: 'thread-9' } }),
  '#/boards/general/threads/thread-9',
);
assert.equal(
  routeToHash({ pageId: PAGE_IDS.deliberation, params: { boardId: 'general', deliberationId: 'deliberation-9' } }),
  '#/boards/general/deliberations/deliberation-9',
);
assert.equal(
  routeToHash({ pageId: PAGE_IDS.profile, params: { did: 'did:elix:Mira' } }),
  '#/profiles/did%3Aelix%3AMira',
);
assert.equal(routeToHash({ pageId: PAGE_IDS.sessions }), '#/sessions');
assert.equal(routeToHash({ pageId: PAGE_IDS.notifications }), '#/notifications');
assert.equal(routeToHash({ pageId: PAGE_IDS.login }), '#/login');
assert.equal(routeToHash({ pageId: PAGE_IDS.moderation }), '#/moderation');
assert.equal(routeToHash({ pageId: PAGE_IDS.faq }), '#/about');
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

const threadCalls = [];
const threadController = createPageController({
  getCurrentHash: () => '#/boards/general/threads/thread-9',
  sessionLifecycle: {
    async restore() {
      threadCalls.push('restore');
      return { status: 'authenticated', viewModel: authenticatedSession };
    },
  },
  forumDataAdapter: {
    async loadThreadPage({ boardId, threadId, sessionViewModel }) {
      threadCalls.push(['thread', boardId, threadId, sessionViewModel.trustTier]);
      return {
        host: { id: 'host-local-dev', displayName: 'Local Forum Host' },
        board: { id: boardId, title: 'General' },
        thread: { id: threadId, title: 'Thread detail' },
        threads: [{ id: threadId, title: 'Thread detail' }],
        capabilities: { canCreateThread: true, canReply: true },
        error: null,
      };
    },
  },
});
const threadState = await threadController.loadCurrentRoute();
assert.deepEqual(threadCalls, ['restore', ['thread', 'general', 'thread-9', 'self_custody_did']]);
assert.equal(threadState.route.pageId, PAGE_IDS.thread);
assert.equal(threadState.viewModel.page.title, 'Thread detail');
assert.equal(threadState.viewModel.thread.id, 'thread-9');
console.log('ok - loads thread detail route data');

const profileCalls = [];
const profileController = createPageController({
  getCurrentHash: () => '#/profiles/did%3Aelix%3AMira',
  sessionLifecycle: {
    async restore() {
      return { status: 'authenticated', viewModel: authenticatedSession };
    },
  },
  forumDataAdapter: {
    async loadProfilePage({ did, sessionViewModel }) {
      profileCalls.push([did, sessionViewModel.trustTier]);
      return {
        profile: { did, displayName: 'Mira' },
        profilePosts: [],
      };
    },
  },
});
const profileState = await profileController.loadCurrentRoute();
assert.deepEqual(profileCalls, [['did:elix:Mira', 'self_custody_did']]);
assert.equal(profileState.route.pageId, PAGE_IDS.profile);
assert.equal(profileState.viewModel.page.title, 'Mira');
console.log('ok - loads the public profile route');

const moderationCalls = [];
const moderationController = createPageController({
  getCurrentHash: () => '#/moderation',
  sessionLifecycle: {
    async restore() {
      return { status: 'authenticated', viewModel: authenticatedSession };
    },
  },
  forumDataAdapter: {
    async loadModerationConsole({ sessionViewModel }) {
      moderationCalls.push(sessionViewModel.trustTier);
      return {
        moderation: {
          status: 'moderator',
          reportGroups: [],
          auditActions: [],
          error: null,
        },
      };
    },
  },
});
const moderationState = await moderationController.loadCurrentRoute();
assert.deepEqual(moderationCalls, ['self_custody_did']);
assert.equal(moderationState.route.pageId, PAGE_IDS.moderation);
assert.equal(moderationState.viewModel.page.id, PAGE_IDS.moderation);
assert.equal(moderationState.viewModel.moderation.status, 'moderator');
console.log('ok - loads the moderation console route');

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

const faqController = createPageController({
  getCurrentHash: () => '#/about',
  sessionLifecycle: {
    async restore() {
      return { status: 'anonymous', viewModel: DEFAULT_SESSION_VIEW_MODEL };
    },
  },
  forumDataAdapter: {},
});
const faqState = await faqController.loadCurrentRoute();
assert.equal(faqState.route.pageId, PAGE_IDS.faq);
assert.equal(faqState.viewModel.page.title, '認識 Elix');
console.log('ok - loads FAQ without forum data');
