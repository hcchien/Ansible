import assert from 'node:assert/strict';

import { createForumUiApp } from '../src/forum_ui_app.mjs';
import { createFrontendFlowHarness } from '../src/integration_flow_harness.mjs';
import { createPageController } from '../src/page_routes.mjs';

const root = createFakeRoot();
const windowLike = createFakeWindow('#/', { dispatchesHashchange: false });
const harness = createFrontendFlowHarness({ routeHash: '#/', sessionMode: 'anonymous' });
const pageController = createPageController({
  getCurrentHash: () => windowLike.location.hash,
  sessionLifecycle: harness.sessionLifecycle,
  forumDataAdapter: harness.forumDataAdapter,
});

const app = createForumUiApp({
  root,
  pageController,
  sessionLifecycle: harness.sessionLifecycle,
  storage: harness.storage,
  windowLike,
});

await app.start();
assert.match(root.innerHTML, /Local Forum Host/);
assert.match(root.innerHTML, /匿名/);
assert.match(root.innerHTML, /href="#\/login"/);
assert.match(root.innerHTML, /class="cols social-home mobile-focus-home"/);
assert.match(root.innerHTML, /RELAY · BOARD · #general/);
assert.match(root.innerHTML, /class="mobile-focus-stage"/);
assert.match(root.innerHTML, /data-active-scene="personal"/);
assert.match(root.innerHTML, /mobile-tabbar/);
assert.doesNotMatch(root.innerHTML, /Mira Lin|FROM A FOLLOW|關於信任的地形|MURMUR · 0:38|AI · 橫向橋/);
assert.doesNotMatch(root.innerHTML, /RELAY · 來源|Relay 資料/);
assert.doesNotMatch(root.innerHTML, /Anonymous|Sign in|Read only|Open board/);

await root.listeners.get('click')({
  target: createContainedActionElement(root, 'select-scene', { scene: 'forum' }),
  preventDefault() {},
});
assert.match(root.innerHTML, /data-active-scene="forum"/);
assert.equal(harness.storage.getItem('elix.focus.active_scene'), 'forum');
await root.listeners.get('pointerdown')({
  target: createFocusStageElement(root),
  clientX: 110,
});
await root.listeners.get('pointerup')({
  target: createFocusStageElement(root),
  clientX: 250,
});
assert.match(root.innerHTML, /data-active-scene="personal"/);
assert.equal(harness.storage.getItem('elix.focus.active_scene'), 'personal');

await app.navigate('#/boards/general');
assert.match(root.innerHTML, /General/);
assert.match(root.innerHTML, /登入後發文/);
assert.match(root.innerHTML, /class="board-head"/);
assert.doesNotMatch(root.innerHTML, /Sign in to post|New thread/);

const postRoot = createFakeRoot();
const postWindow = createFakeWindow('#/boards/general', {
  dispatchesHashchange: false,
});
const postHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'approvedDid',
});
let submittedDraft = null;
const postingAdapter = {
  ...postHarness.forumDataAdapter,
  async submitThreadDraft(params) {
    submittedDraft = params;
    return {
      accepted: true,
      subjectDid: 'did:plc:fixture',
      trustTier: 'self_custody_did',
    };
  },
};
const postPageController = createPageController({
  getCurrentHash: () => postWindow.location.hash,
  sessionLifecycle: postHarness.sessionLifecycle,
  forumDataAdapter: postingAdapter,
});
const postApp = createForumUiApp({
  root: postRoot,
  pageController: postPageController,
  sessionLifecycle: postHarness.sessionLifecycle,
  forumDataAdapter: postingAdapter,
  storage: postHarness.storage,
  windowLike: postWindow,
});
await postApp.start();
await postRoot.listeners.get('click')({
  target: createContainedActionElement(postRoot, 'new-thread', {
    boardId: 'general',
  }),
  preventDefault() {},
});
assert.match(postRoot.innerHTML, /data-thread-draft-form/);

await postRoot.listeners.get('click')({
  target: createContainedActionElement(postRoot, 'submit-thread-draft', {
    boardId: 'general',
    title: 'Web posted thread',
  }),
  preventDefault() {},
});
assert.equal(submittedDraft, null);
assert.match(postRoot.innerHTML, /確認即將簽署的發布內容/);

await postRoot.listeners.get('click')({
  target: createContainedActionElement(postRoot, 'confirm-thread-draft', {
    boardId: 'general',
  }),
  preventDefault() {},
});
assert.equal(submittedDraft.title, 'Web posted thread');
assert.equal(submittedDraft.boardId, 'general');
assert.equal(submittedDraft.sessionViewModel.authenticated, true);
assert.match(postRoot.innerHTML, /已送出討論串/);
postApp.stop();

await app.navigate('#/login');
assert.match(root.innerHTML, /產生登入 QR code/);
assert.match(root.innerHTML, /class="login-grid"/);

await app.startLogin();
assert.match(root.innerHTML, /用 Elix app 登入/);
assert.match(root.innerHTML, /wsc_fixture/);
assert.match(root.innerHTML, /class="challenge-payload-preview"/);
assert.match(root.innerHTML, /class="qr-code"/);
assert.match(root.innerHTML, /用 Elix app 掃描/);
assert.match(root.innerHTML, /我已在 app 核准/);
assert.doesNotMatch(root.innerHTML, /data-action="start-login"/);
assert.doesNotMatch(root.innerHTML, /登入挑戰|建立挑戰|有效挑戰|Start app login|App login challenge|Scan with Elix app/);
assert.doesNotMatch(root.innerHTML, /Deep link|QR payload|Open in app/);
assert.doesNotMatch(root.innerHTML, /trisaura:\/\/web-session\/approve/);

await app.pollLoginOnce();
assert.match(root.innerHTML, /自持有 DID/);
await app.navigate('#/sessions');
assert.match(root.innerHTML, /class="settings-home"/);
assert.match(root.innerHTML, /每版的光/);
await root.listeners.get('click')({
  target: createContainedActionElement(root, 'set-scene-theme', {
    scene: 'personal',
    theme: 'dark',
  }),
  preventDefault() {},
});
assert.match(root.innerHTML, /data-personal-theme="dark"/);
assert.equal(harness.storage.getItem('elix.focus.personal_theme'), 'dark');
await root.listeners.get('click')({
  target: createContainedActionElement(root, 'set-motion-mode', { motion: 'book' }),
  preventDefault() {},
});
assert.match(root.innerHTML, /data-motion-mode="book"/);
assert.equal(harness.storage.getItem('elix.focus.motion_mode'), 'book');

app.stop();

const hashRoot = createFakeRoot();
const hashWindow = createFakeWindow('#/', { dispatchesHashchange: true });
let routeLoadCount = 0;
const hashHarness = createFrontendFlowHarness({ routeHash: '#/', sessionMode: 'anonymous' });
const hashPageController = createPageController({
  getCurrentHash: () => hashWindow.location.hash,
  sessionLifecycle: hashHarness.sessionLifecycle,
  forumDataAdapter: hashHarness.forumDataAdapter,
});
const countedPageController = {
  ...hashPageController,
  async loadCurrentRoute() {
    routeLoadCount += 1;
    return hashPageController.loadCurrentRoute();
  },
};
const hashApp = createForumUiApp({
  root: hashRoot,
  pageController: countedPageController,
  sessionLifecycle: hashHarness.sessionLifecycle,
  storage: hashHarness.storage,
  windowLike: hashWindow,
});
await hashApp.start();
assert.equal(routeLoadCount, 1);
await hashApp.navigate('#/boards/general');
assert.equal(routeLoadCount, 2);
assert.match(hashRoot.innerHTML, /General/);
hashApp.stop();

const failureRoot = createFakeRoot();
const failureWindow = createFakeWindow('#/login', { dispatchesHashchange: false });
const failureHarness = createFrontendFlowHarness({ routeHash: '#/login', sessionMode: 'anonymous' });
const failurePageController = createPageController({
  getCurrentHash: () => failureWindow.location.hash,
  sessionLifecycle: failureHarness.sessionLifecycle,
  forumDataAdapter: failureHarness.forumDataAdapter,
});
const failureApp = createForumUiApp({
  root: failureRoot,
  pageController: failurePageController,
  sessionLifecycle: {
    ...failureHarness.sessionLifecycle,
    async pollLoginChallenge() {
      throw new Error('poll failed');
    },
  },
  storage: failureHarness.storage,
  windowLike: failureWindow,
});
await failureApp.start();
await failureApp.startLogin();
await assert.rejects(() => failureApp.pollLoginOnce(), /poll failed/);
assert.match(failureRoot.innerHTML, /Forum 錯誤/);
assert.match(failureRoot.innerHTML, /poll failed/);
await failureRoot.listeners.get('click')({
  target: createContainedActionElement(failureRoot, 'poll-login'),
  preventDefault() {},
});
assert.match(failureRoot.innerHTML, /poll failed/);
failureApp.stop();

const scopedRoot = createFakeRoot();
const scopedWindow = createFakeWindow('#/login', { dispatchesHashchange: false });
let outsideStarted = false;
const scopedHarness = createFrontendFlowHarness({ routeHash: '#/login', sessionMode: 'anonymous' });
const scopedPageController = createPageController({
  getCurrentHash: () => scopedWindow.location.hash,
  sessionLifecycle: scopedHarness.sessionLifecycle,
  forumDataAdapter: scopedHarness.forumDataAdapter,
});
const outsideAction = createOutsideActionElement('start-login');
const scopedApp = createForumUiApp({
  root: scopedRoot,
  pageController: scopedPageController,
  sessionLifecycle: {
    ...scopedHarness.sessionLifecycle,
    async startAppLogin() {
      outsideStarted = true;
      return scopedHarness.sessionLifecycle.startAppLogin();
    },
  },
  storage: scopedHarness.storage,
  windowLike: scopedWindow,
});
await scopedApp.start();
await scopedRoot.listeners.get('click')({
  target: { closest: () => outsideAction },
  preventDefault() {
    throw new Error('outside action should not be handled');
  },
});
assert.equal(outsideStarted, false);
scopedApp.stop();

const moderationRoot = createFakeRoot();
const moderationWindow = createFakeWindow('#/moderation', { dispatchesHashchange: false });
const moderationHarness = createFrontendFlowHarness({
  routeHash: '#/moderation',
  sessionMode: 'approvedDid',
});
const moderationPageController = createPageController({
  getCurrentHash: () => moderationWindow.location.hash,
  sessionLifecycle: moderationHarness.sessionLifecycle,
  forumDataAdapter: moderationHarness.forumDataAdapter,
});
const moderationApp = createForumUiApp({
  root: moderationRoot,
  pageController: moderationPageController,
  sessionLifecycle: moderationHarness.sessionLifecycle,
  forumDataAdapter: moderationHarness.forumDataAdapter,
  storage: moderationHarness.storage,
  windowLike: moderationWindow,
});

await moderationApp.start();
assert.match(moderationRoot.innerHTML, /板務主控台/);
assert.match(moderationRoot.innerHTML, /待處理檢舉 · 3/);
assert.match(moderationRoot.innerHTML, /data-mod-action="dismiss_report"/);
assert.match(moderationRoot.innerHTML, /處理紀錄/);

await moderationRoot.listeners.get('click')({
  target: createContainedActionElement(moderationRoot, 'moderation-action', {
    modAction: 'lock_thread',
    reportId: '42',
    targetRef: 'thread-9',
    boardId: 'general',
    reasonCode: 'harassment',
  }),
  preventDefault() {},
});
assert.match(moderationRoot.innerHTML, /已記錄板務動作/);
assert.match(moderationRoot.innerHTML, /鎖定討論串/);

await moderationApp.navigate('#/boards/general');
await moderationRoot.listeners.get('click')({
  target: createContainedActionElement(moderationRoot, 'submit-report', {
    targetKind: 'thread',
    targetRef: 'thread-9',
    boardId: 'general',
    reasonCode: 'spam',
  }),
  preventDefault() {},
});
assert.match(moderationRoot.innerHTML, /已送出檢舉/);

await moderationRoot.listeners.get('click')({
  target: createContainedActionElement(moderationRoot, 'submit-report', {
    targetKind: 'thread',
    targetRef: 'thread-9',
    boardId: 'general',
    reasonCode: 'other',
    note: '',
  }),
  preventDefault() {},
});
assert.match(moderationRoot.innerHTML, /檢舉未送出|選擇「其他」時/);
moderationApp.stop();

console.log('ok - forum UI app controller');

function createFakeRoot() {
  return {
    innerHTML: '',
    listeners: new Map(),
    contains(node) {
      let current = node;
      while (current) {
        if (current === this) return true;
        current = current.parentElement;
      }
      return false;
    },
    addEventListener(type, listener) {
      this.listeners.set(type, listener);
    },
    removeEventListener(type, listener) {
      if (this.listeners.get(type) === listener) {
        this.listeners.delete(type);
      }
    },
  };
}

function createFakeWindow(hash, { dispatchesHashchange = false } = {}) {
  const listeners = new Map();
  const location = {};
  Object.defineProperty(location, 'hash', {
    get() {
      return hash;
    },
    set(value) {
      const previousHash = hash;
      hash = value;
      if (dispatchesHashchange && previousHash !== value) {
        listeners.get('hashchange')?.();
      }
    },
  });

  return {
    dispatchesHashchange,
    location,
    listeners,
    addEventListener(type, listener) {
      this.listeners.set(type, listener);
    },
    removeEventListener(type, listener) {
      if (this.listeners.get(type) === listener) {
        this.listeners.delete(type);
      }
    },
    setInterval() {
      return 1;
    },
    clearInterval() {},
  };
}

function createContainedActionElement(root, action, dataset = {}) {
  return {
    dataset: { ...dataset, action },
    parentElement: root,
  };
}

function createOutsideActionElement(action) {
  return {
    dataset: { action },
    parentElement: null,
  };
}

function createFocusStageElement(root) {
  const stage = {
    className: 'mobile-focus-stage',
    parentElement: root,
  };

  return {
    parentElement: stage,
    closest(selector) {
      return selector === '.mobile-focus-stage' ? stage : null;
    },
  };
}
