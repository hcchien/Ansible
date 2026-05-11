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
assert.match(root.innerHTML, /Anonymous/);
assert.match(root.innerHTML, /href="#\/login"/);

await app.navigate('#/boards/general');
assert.match(root.innerHTML, /General/);
assert.match(root.innerHTML, /Sign in to post/);

await app.navigate('#/login');
assert.match(root.innerHTML, /Start app login/);

await app.startLogin();
assert.match(root.innerHTML, /App login challenge/);
assert.match(root.innerHTML, /wsc_fixture/);

await app.pollLoginOnce();
assert.match(root.innerHTML, /Self-custody DID/);

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
assert.match(failureRoot.innerHTML, /Forum error/);
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

function createContainedActionElement(root, action) {
  return {
    dataset: { action },
    parentElement: root,
  };
}

function createOutsideActionElement(action) {
  return {
    dataset: { action },
    parentElement: null,
  };
}
