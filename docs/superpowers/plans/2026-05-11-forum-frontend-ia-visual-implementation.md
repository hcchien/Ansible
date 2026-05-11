# Forum Frontend IA Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved forum-first network-console UI on top of the existing frontend route skeleton without adding new routes or backend dependencies.

**Architecture:** Add pure renderer modules for shell, pages, and UI text so the visual IA can be tested without a browser DOM. Add a small UI app controller that wires the existing `page_routes`, `session_lifecycle`, and `forum_data_adapter` modules into `index.html`. Keep `#/login` as the dedicated challenge page and keep all route decisions in the current route skeleton.

**Tech Stack:** Plain ES modules, static HTML, CSS, existing frontend API/view-model modules, fixture clients, Node test runner style via `node path/to/test.mjs`.

---

## Source Documents

Read these first:

- `docs/superpowers/specs/2026-05-11-forum-frontend-ia-visual-design.md`
- `docs/superpowers/specs/2026-05-11-web-development-design.md`
- `docs/superpowers/specs/2026-05-11-app-mediated-web-session-design.md`
- `ansible_distribution_frontend/src/state_model.mjs`
- `ansible_distribution_frontend/src/page_routes.mjs`
- `ansible_distribution_frontend/src/session_lifecycle.mjs`
- `ansible_distribution_frontend/src/forum_data_adapter.mjs`
- `ansible_distribution_frontend/src/contract_fixtures.mjs`
- `ansible_distribution_frontend/src/integration_flow_harness.mjs`

## Scope Check

This plan only implements the approved IA and visual design for the current
frontend route skeleton:

- `#/`
- `#/boards`
- `#/boards/:boardId`
- `#/login`
- `#/sessions`
- fallback Not found

Do not add diagnostics, profile, thread detail, notification, moderation,
settings, or admin routes in this implementation pass.

## File Structure

Create focused frontend UI modules:

- Create `ansible_distribution_frontend/src/forum_ui_text.mjs`.
  Owns text formatting, DID/token shortening, origin labels, scope labels, and
  error copy derived from the frontend error taxonomy.
- Create `ansible_distribution_frontend/src/forum_shell_renderer.mjs`.
  Owns HTML escaping, command header rendering, session chip rendering, action
  rendering, and root shell composition.
- Create `ansible_distribution_frontend/src/forum_page_renderers.mjs`.
  Owns route-specific page HTML for Home, Boards, Board, Login, Sessions, and
  Not Found.
- Create `ansible_distribution_frontend/src/forum_ui_app.mjs`.
  Owns DOM wiring, route loading, hash navigation, login actions, polling,
  sign-out, revoke, and rerendering.
- Modify `ansible_distribution_frontend/src/main.mjs`.
  Replace the login-smoke-only bootstrap with the new UI app bootstrap.
- Modify `ansible_distribution_frontend/index.html`.
  Replace the current login-only markup with a root mount point and config
  inputs that can be used by the UI app.
- Modify `ansible_distribution_frontend/src/styles.css`.
  Implement the approved network-console visual system, command header, route
  pages, login challenge, sessions page, error states, and responsive behavior.

Create focused tests:

- Create `ansible_distribution_frontend/test/forum_ui_text.test.mjs`.
- Create `ansible_distribution_frontend/test/forum_shell_renderer.test.mjs`.
- Create `ansible_distribution_frontend/test/forum_page_renderers.test.mjs`.
- Create `ansible_distribution_frontend/test/forum_ui_app.test.mjs`.
- Modify `ansible_distribution_frontend/test/css_contract.test.mjs`.
- Keep existing API, route, fixture, and integration tests passing.

## Task 1: UI Text Helpers

**Files:**

- Create `ansible_distribution_frontend/src/forum_ui_text.mjs`.
- Test `ansible_distribution_frontend/test/forum_ui_text.test.mjs`.

- [ ] **Step 1: Write the failing text-helper tests**

Create `ansible_distribution_frontend/test/forum_ui_text.test.mjs`:

```js
import assert from 'node:assert/strict';

import {
  describeError,
  formatExpiry,
  formatScope,
  shortIdentity,
  trustTierLabel,
} from '../src/forum_ui_text.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';

assert.equal(shortIdentity(null), 'Anonymous');
assert.equal(shortIdentity('did:plc:fixtureabcdef'), 'did:plc...abcdef');
assert.equal(trustTierLabel('self_custody_did'), 'Self-custody DID');
assert.equal(trustTierLabel('anonymous'), 'Anonymous');
assert.equal(formatScope('forum:post'), 'Post threads');
assert.equal(formatScope('identity:display'), 'Display identity');
assert.equal(formatExpiry('2026-05-12T01:00:00Z'), '2026-05-12 01:00 UTC');

assert.deepEqual(
  describeError({
    type: ERROR_TYPES.missingScope,
    detail: { requiredScope: 'forum:post' },
  }),
  {
    tone: 'warning',
    title: 'Sign in required',
    message: 'This action needs the Post threads scope.',
  },
);

assert.deepEqual(
  describeError({ type: ERROR_TYPES.unauthenticated }),
  {
    tone: 'danger',
    title: 'Session unavailable',
    message: 'Start a new app-approved browser session to continue.',
  },
);

console.log('ok - forum UI text helpers');
```

- [ ] **Step 2: Run the failing text-helper test**

Run:

```bash
node ansible_distribution_frontend/test/forum_ui_text.test.mjs
```

Expected: fail with `Cannot find module '../src/forum_ui_text.mjs'`.

- [ ] **Step 3: Implement the text helpers**

Create `ansible_distribution_frontend/src/forum_ui_text.mjs`:

```js
import { ERROR_TYPES } from './error_taxonomy.mjs';

const SCOPE_LABELS = Object.freeze({
  'forum:read': 'Read forum',
  'forum:post': 'Post threads',
  'forum:reply': 'Reply',
  'identity:display': 'Display identity',
  'session:revoke': 'Revoke sessions',
});

const TRUST_TIER_LABELS = Object.freeze({
  anonymous: 'Anonymous',
  basic_web: 'Basic web',
  web_passkey: 'Web passkey',
  self_custody_did: 'Self-custody DID',
  verified_human: 'Verified human',
});

export function shortIdentity(value) {
  if (!value) return 'Anonymous';
  if (value.length <= 16) return value;
  return `${value.slice(0, 7)}...${value.slice(-6)}`;
}

export function trustTierLabel(value) {
  return TRUST_TIER_LABELS[value] ?? value ?? 'Anonymous';
}

export function formatScope(scope) {
  return SCOPE_LABELS[scope] ?? scope;
}

export function formatExpiry(value) {
  if (!value) return 'No expiry';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
}

export function describeError(error) {
  if (!error) return null;

  if (error.type === ERROR_TYPES.missingScope) {
    const scope = formatScope(error.detail?.requiredScope);
    return {
      tone: 'warning',
      title: 'Sign in required',
      message: `This action needs the ${scope} scope.`,
    };
  }

  if (error.type === ERROR_TYPES.unauthenticated) {
    return {
      tone: 'danger',
      title: 'Session unavailable',
      message: 'Start a new app-approved browser session to continue.',
    };
  }

  if (error.type === ERROR_TYPES.notFound) {
    return {
      tone: 'danger',
      title: 'Not found',
      message: 'This forum route or resource is unavailable.',
    };
  }

  if (error.type === ERROR_TYPES.rateLimited) {
    return {
      tone: 'warning',
      title: 'Rate limited',
      message: 'Wait before retrying this forum action.',
    };
  }

  return {
    tone: 'danger',
    title: 'Forum error',
    message: error.message || 'The forum frontend could not complete the request.',
  };
}
```

- [ ] **Step 4: Verify the text-helper test passes**

Run:

```bash
node ansible_distribution_frontend/test/forum_ui_text.test.mjs
```

Expected: pass with `ok - forum UI text helpers`.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add ansible_distribution_frontend/src/forum_ui_text.mjs ansible_distribution_frontend/test/forum_ui_text.test.mjs
git commit -m "feat(frontend): add forum UI text helpers"
```

## Task 2: Command Header And Shell Renderer

**Files:**

- Create `ansible_distribution_frontend/src/forum_shell_renderer.mjs`.
- Test `ansible_distribution_frontend/test/forum_shell_renderer.test.mjs`.

- [ ] **Step 1: Write the failing shell renderer tests**

Create `ansible_distribution_frontend/test/forum_shell_renderer.test.mjs`:

```js
import assert from 'node:assert/strict';

import { renderAppShell, renderCommandHeader } from '../src/forum_shell_renderer.mjs';
import { buildAppViewModel, PAGE_IDS } from '../src/state_model.mjs';
import { DEFAULT_SESSION_VIEW_MODEL } from '../src/session_lifecycle.mjs';

const anonymousVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.home, params: {} },
  session: DEFAULT_SESSION_VIEW_MODEL,
  forum: {
    host: { displayName: 'Local Forum Host' },
    boards: [{ id: 'general', title: 'General' }],
    capabilities: { canCreateThread: false, canReply: false },
  },
});

const header = renderCommandHeader(anonymousVm);
assert.match(header, /Forum Relay|Local Forum Host/);
assert.match(header, /href="#\/boards"/);
assert.match(header, /Anonymous/);
assert.match(header, /Sign in/);
assert.doesNotMatch(header, /Diagnostics|Profile|Settings/);

const authenticatedVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.board, params: { boardId: 'general' } },
  session: {
    authenticated: true,
    subjectDid: 'did:plc:fixtureabcdef',
    trustTier: 'self_custody_did',
    scopes: ['forum:post'],
    capabilities: { canRevoke: true },
  },
  forum: {
    board: { id: 'general', title: 'General' },
    threads: [],
    capabilities: { canCreateThread: true, canReply: false },
  },
});

const shell = renderAppShell({
  viewModel: authenticatedVm,
  bodyHtml: '<section class="page-panel">Body</section>',
});
assert.match(shell, /Self-custody DID/);
assert.match(shell, /New thread/);
assert.match(shell, /<section class="page-panel">Body<\/section>/);

const escaped = renderAppShell({
  viewModel: {
    ...anonymousVm,
    page: { ...anonymousVm.page, title: '<script>alert(1)</script>' },
  },
  bodyHtml: '<p>Safe body</p>',
});
assert.doesNotMatch(escaped, /<script>/);
assert.match(escaped, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);

console.log('ok - forum shell renderer');
```

- [ ] **Step 2: Run the failing shell renderer test**

Run:

```bash
node ansible_distribution_frontend/test/forum_shell_renderer.test.mjs
```

Expected: fail with `Cannot find module '../src/forum_shell_renderer.mjs'`.

- [ ] **Step 3: Implement the shell renderer**

Create `ansible_distribution_frontend/src/forum_shell_renderer.mjs`:

```js
import { shortIdentity, trustTierLabel } from './forum_ui_text.mjs';

export function renderAppShell({ viewModel, bodyHtml }) {
  return `
    <div class="forum-shell">
      ${renderCommandHeader(viewModel)}
      <main class="forum-main" aria-labelledby="page-title">
        <div class="page-heading">
          <p class="section-label">${escapeHtml(viewModel.page.id)}</p>
          <h1 id="page-title">${escapeHtml(viewModel.page.title)}</h1>
        </div>
        ${bodyHtml}
      </main>
    </div>
  `;
}

export function renderCommandHeader(viewModel) {
  const label = viewModel.host?.displayName || 'Forum Relay';
  const nav = viewModel.navigation
    .map((item) => {
      const current = item.id === viewModel.page.id ? ' aria-current="page"' : '';
      return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
    })
    .join('');

  return `
    <header class="command-header">
      <a class="brand-lockup" href="#/">${escapeHtml(label)}</a>
      <nav class="command-nav" aria-label="Forum">${nav}</nav>
      <div class="command-context">
        <span class="route-title">${escapeHtml(viewModel.page.title)}</span>
        ${renderSessionChip(viewModel.session)}
        ${renderPrimaryAction(viewModel)}
      </div>
    </header>
  `;
}

export function renderSessionChip(session) {
  if (!session?.authenticated) {
    return '<a class="session-chip is-anonymous" href="#/login"><span>Anonymous</span><strong>Read only</strong></a>';
  }

  return `
    <a class="session-chip is-authenticated" href="#/sessions">
      <span>${escapeHtml(shortIdentity(session.subjectDid || session.subject))}</span>
      <strong>${escapeHtml(trustTierLabel(session.trustTier))}</strong>
    </a>
  `;
}

export function renderPrimaryAction(viewModel) {
  if (viewModel.actions?.canCreateThread) {
    return '<button class="header-action" type="button" data-action="new-thread">New thread</button>';
  }

  if (viewModel.actions?.canRevokeSession && viewModel.page.id === 'sessions') {
    return '<button class="header-action is-danger" type="button" data-action="revoke-session">Revoke</button>';
  }

  if (viewModel.actions?.showLogin) {
    return '<a class="header-action" href="#/login">Sign in</a>';
  }

  return '';
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll('`', '&#96;');
}
```

- [ ] **Step 4: Verify shell renderer tests pass**

Run:

```bash
node ansible_distribution_frontend/test/forum_shell_renderer.test.mjs
```

Expected: pass with `ok - forum shell renderer`.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add ansible_distribution_frontend/src/forum_shell_renderer.mjs ansible_distribution_frontend/test/forum_shell_renderer.test.mjs
git commit -m "feat(frontend): add forum command shell renderer"
```

## Task 3: Route Page Renderers

**Files:**

- Create `ansible_distribution_frontend/src/forum_page_renderers.mjs`.
- Test `ansible_distribution_frontend/test/forum_page_renderers.test.mjs`.

- [ ] **Step 1: Write the failing page renderer tests**

Create `ansible_distribution_frontend/test/forum_page_renderers.test.mjs`:

```js
import assert from 'node:assert/strict';

import { renderPageBody } from '../src/forum_page_renderers.mjs';
import { createFrontendFlowHarness, runBoardRouteFlow, runPublicHomeFlow } from '../src/integration_flow_harness.mjs';
import { PAGE_IDS, buildAppViewModel } from '../src/state_model.mjs';

const homeHarness = createFrontendFlowHarness({
  routeHash: '#/',
  sessionMode: 'anonymous',
});
const homeState = await runPublicHomeFlow(homeHarness);
const homeHtml = renderPageBody(homeState.viewModel);
assert.match(homeHtml, /Local Forum Host/);
assert.match(homeHtml, /General/);
assert.match(homeHtml, /Read only/);
assert.doesNotMatch(homeHtml, /App-approved web session login/);

const boardHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'approvedDid',
});
const boardState = await runBoardRouteFlow(boardHarness);
const boardHtml = renderPageBody(boardState.viewModel);
assert.match(boardHtml, /General/);
assert.match(boardHtml, /New thread/);
assert.match(boardHtml, /Self-custody DID/);

const loginVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.login, params: {} },
  session: { authenticated: false, status: 'pending', scopes: [] },
  forum: null,
});
const loginHtml = renderPageBody(loginVm, {
  login: {
    status: 'pending',
    challenge: {
      challengeId: 'wsc_fixture',
      expiresAt: '2026-05-12T01:00:00Z',
      deepLink: 'trisaura://web-session/approve?challenge_id=wsc_fixture',
      qrPayload: 'trisaura://web-session/approve?challenge_id=wsc_fixture',
    },
    requestedScopes: ['forum:read', 'forum:post', 'forum:reply', 'identity:display'],
  },
});
assert.match(loginHtml, /App login challenge/);
assert.match(loginHtml, /wsc_fixture/);
assert.match(loginHtml, /Post threads/);

const sessionsVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.sessions, params: {} },
  session: {
    authenticated: true,
    subjectDid: 'did:plc:fixtureabcdef',
    trustTier: 'self_custody_did',
    scopes: ['forum:post', 'session:revoke'],
    expiresAt: '2026-05-12T01:00:00Z',
    capabilities: { canRevoke: true },
  },
  forum: null,
});
const sessionsHtml = renderPageBody(sessionsVm);
assert.match(sessionsHtml, /Self-custody DID/);
assert.match(sessionsHtml, /Post threads/);
assert.match(sessionsHtml, /Revoke current session/);

const notFoundVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.notFound, params: { path: '/missing' } },
  session: { authenticated: false },
  forum: null,
});
assert.match(renderPageBody(notFoundVm), /Route unavailable/);

console.log('ok - forum page renderers');
```

- [ ] **Step 2: Run the failing page renderer test**

Run:

```bash
node ansible_distribution_frontend/test/forum_page_renderers.test.mjs
```

Expected: fail with `Cannot find module '../src/forum_page_renderers.mjs'`.

- [ ] **Step 3: Implement route page renderers**

Create `ansible_distribution_frontend/src/forum_page_renderers.mjs` with these
exports:

```js
import { PAGE_IDS } from './state_model.mjs';
import { describeError, formatExpiry, formatScope, shortIdentity, trustTierLabel } from './forum_ui_text.mjs';
import { escapeHtml } from './forum_shell_renderer.mjs';

export function renderPageBody(viewModel, uiState = {}) {
  const errorHtml = renderError(viewModel.error);

  switch (viewModel.page.id) {
    case PAGE_IDS.home:
      return `${errorHtml}${renderHome(viewModel)}`;
    case PAGE_IDS.boards:
      return `${errorHtml}${renderBoards(viewModel)}`;
    case PAGE_IDS.board:
      return `${errorHtml}${renderBoard(viewModel)}`;
    case PAGE_IDS.login:
      return `${errorHtml}${renderLogin(viewModel, uiState.login)}`;
    case PAGE_IDS.sessions:
      return `${errorHtml}${renderSessions(viewModel)}`;
    default:
      return `${errorHtml}${renderNotFound(viewModel)}`;
  }
}
```

Implement the page functions with these stable class names and required data
attributes:

```js
function renderHome(viewModel) {
  return `
    <section class="page-panel host-panel">
      <div>
        <p class="section-label">Forum host</p>
        <h2>${escapeHtml(viewModel.host?.displayName || 'Forum Relay')}</h2>
        <p>Browse public boards. Sign in only when you post or manage sessions.</p>
      </div>
      <a class="panel-action" href="#/boards">Browse boards</a>
    </section>
    ${renderBoardDirectory(viewModel.boards, viewModel)}
  `;
}

function renderBoards(viewModel) {
  return `
    <section class="page-panel">
      <p class="section-label">Board directory</p>
      <h2>Boards</h2>
      ${renderBoardDirectory(viewModel.boards, viewModel)}
    </section>
  `;
}

function renderBoard(viewModel) {
  const canCreate = viewModel.actions?.canCreateThread;
  return `
    <section class="page-panel board-panel">
      <div class="panel-header">
        <div>
          <p class="section-label">Board</p>
          <h2>${escapeHtml(viewModel.board?.title || viewModel.page.title)}</h2>
        </div>
        ${
          canCreate
            ? '<button type="button" class="panel-action" data-action="new-thread">New thread</button>'
            : '<a class="panel-action is-muted" href="#/login">Sign in to post</a>'
        }
      </div>
      <div class="thread-list">
        ${
          viewModel.threads.length
            ? viewModel.threads.map(renderThreadRow).join('')
            : '<p class="empty-state">No public threads are available for this board yet.</p>'
        }
      </div>
    </section>
  `;
}
```

Also implement `renderLogin`, `renderSessions`, `renderNotFound`,
`renderBoardDirectory`, `renderThreadRow`, and `renderError` in the same module.
Use these rules:

- `renderLogin` shows a `Start app login` button with `data-action="start-login"`.
- Pending login shows challenge id, expiry, deep link, QR payload, and scope
  chips using `formatScope`.
- Rejected and expired login states show a retry button.
- `renderSessions` shows subject DID, trust tier, scopes, expiry, and a
  `data-action="revoke-session"` button when revocation is allowed.
- `renderError` uses `describeError` and emits
  `<aside class="error-banner is-${tone}" role="status">`.
- All dynamic strings pass through `escapeHtml`.

- [ ] **Step 4: Verify page renderer tests pass**

Run:

```bash
node ansible_distribution_frontend/test/forum_page_renderers.test.mjs
```

Expected: pass with `ok - forum page renderers`.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
git add ansible_distribution_frontend/src/forum_page_renderers.mjs ansible_distribution_frontend/test/forum_page_renderers.test.mjs
git commit -m "feat(frontend): render forum route pages"
```

## Task 4: UI App Controller And Bootstrap

**Files:**

- Create `ansible_distribution_frontend/src/forum_ui_app.mjs`.
- Modify `ansible_distribution_frontend/src/main.mjs`.
- Modify `ansible_distribution_frontend/index.html`.
- Test `ansible_distribution_frontend/test/forum_ui_app.test.mjs`.

- [ ] **Step 1: Write the failing UI app test**

Create `ansible_distribution_frontend/test/forum_ui_app.test.mjs`:

```js
import assert from 'node:assert/strict';

import { createForumUiApp } from '../src/forum_ui_app.mjs';
import { createFrontendFlowHarness } from '../src/integration_flow_harness.mjs';

function createRoot() {
  return {
    innerHTML: '',
    listeners: new Map(),
    addEventListener(type, handler) {
      this.listeners.set(type, handler);
    },
    querySelector() {
      return null;
    },
  };
}

const root = createRoot();
const harness = createFrontendFlowHarness({
  routeHash: '#/',
  sessionMode: 'anonymous',
});
let hash = '#/';
const windowLike = {
  location: { hash },
  addEventListener() {},
};

const app = createForumUiApp({
  root,
  pageController: harness.pageController,
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

console.log('ok - forum UI app controller');
```

- [ ] **Step 2: Run the failing UI app test**

Run:

```bash
node ansible_distribution_frontend/test/forum_ui_app.test.mjs
```

Expected: fail with `Cannot find module '../src/forum_ui_app.mjs'`.

- [ ] **Step 3: Implement the UI app controller**

Create `ansible_distribution_frontend/src/forum_ui_app.mjs`:

```js
import { renderAppShell } from './forum_shell_renderer.mjs';
import { renderPageBody } from './forum_page_renderers.mjs';
import { WEB_SESSION_TOKEN_KEY } from './web_session_client.mjs';

export function createForumUiApp({
  root,
  pageController,
  sessionLifecycle,
  storage,
  windowLike = globalThis.window,
}) {
  let state = null;
  let loginState = { status: 'signed_out', requestedScopes: [] };
  let pollTimer = null;

  async function start() {
    bindEvents();
    await loadCurrentRoute();
  }

  async function navigate(hash) {
    windowLike.location.hash = hash;
    await loadCurrentRoute();
  }

  async function loadCurrentRoute() {
    state = await pageController.loadCurrentRoute();
    render();
    return state;
  }

  async function startLogin() {
    loginState = await sessionLifecycle.startAppLogin();
    render();
    return loginState;
  }

  async function pollLoginOnce() {
    loginState = await sessionLifecycle.pollLoginChallenge();
    render();
    return loginState;
  }

  async function revokeSession() {
    await sessionLifecycle.revokeCurrentSession();
    await loadCurrentRoute();
  }

  function signOut() {
    storage?.removeItem?.(WEB_SESSION_TOKEN_KEY);
    return loadCurrentRoute();
  }

  function render() {
    const viewModel = state?.viewModel ?? pageController.getState().viewModel;
    const bodyHtml = renderPageBody(viewModel, { login: loginState });
    root.innerHTML = renderAppShell({ viewModel, bodyHtml });
  }

  function bindEvents() {
    root.addEventListener?.('click', async (event) => {
      const target = event.target?.closest?.('[data-action]');
      if (!target) return;
      const action = target.dataset.action;
      if (action === 'start-login') await startLogin();
      if (action === 'poll-login') await pollLoginOnce();
      if (action === 'revoke-session') await revokeSession();
      if (action === 'sign-out') await signOut();
    });

    windowLike.addEventListener?.('hashchange', loadCurrentRoute);
  }

  function stop() {
    if (pollTimer) {
      windowLike.clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  return {
    start,
    navigate,
    loadCurrentRoute,
    startLogin,
    pollLoginOnce,
    revokeSession,
    signOut,
    stop,
  };
}
```

The function names in this controller match the existing
`session_lifecycle.mjs` API: `startAppLogin`, `pollLoginChallenge`, and
`revokeCurrentSession`. Keep root rendering as a replace-all strategy for this
pass.

- [ ] **Step 4: Replace the static login-only bootstrap**

Modify `ansible_distribution_frontend/index.html` so `<body>` contains:

```html
<body>
  <div id="forum-root" class="app-shell"></div>
  <script type="module" src="./src/main.mjs"></script>
</body>
```

Modify `ansible_distribution_frontend/src/main.mjs` so it creates the real app:

```js
import { createForumDataAdapter } from './forum_data_adapter.mjs';
import { createForumUiApp } from './forum_ui_app.mjs';
import { createPageController } from './page_routes.mjs';
import { createSessionLifecycle } from './session_lifecycle.mjs';

const root = document.querySelector('#forum-root');
const relayBaseUrl = localStorage.getItem('trisaura.relay_base_url') ?? 'http://localhost:4001';
const webOrigin = window.location.origin;

const sessionLifecycle = createSessionLifecycle({
  relayBaseUrl,
  webOrigin,
  storage: localStorage,
});
const forumDataAdapter = createForumDataAdapter({
  relayBaseUrl,
  storage: localStorage,
});
const pageController = createPageController({
  sessionLifecycle,
  forumDataAdapter,
});

createForumUiApp({
  root,
  pageController,
  sessionLifecycle,
  storage: localStorage,
  windowLike: window,
}).start();
```

- [ ] **Step 5: Verify UI app tests pass**

Run:

```bash
node ansible_distribution_frontend/test/forum_ui_app.test.mjs
```

Expected: pass with `ok - forum UI app controller`.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add ansible_distribution_frontend/src/forum_ui_app.mjs ansible_distribution_frontend/src/main.mjs ansible_distribution_frontend/index.html ansible_distribution_frontend/test/forum_ui_app.test.mjs
git commit -m "feat(frontend): wire forum UI app shell"
```

## Task 5: Network Console CSS And Responsive Contracts

**Files:**

- Modify `ansible_distribution_frontend/src/styles.css`.
- Modify `ansible_distribution_frontend/test/css_contract.test.mjs`.

- [ ] **Step 1: Write failing CSS contract assertions**

Extend `ansible_distribution_frontend/test/css_contract.test.mjs`:

```js
assert.match(css, /--background:\s*#0f1720;/, 'network console background token is required');
assert.match(css, /--surface:\s*#142230;/, 'network console surface token is required');
assert.match(css, /--accent:\s*#7dd3c7;/, 'network console accent token is required');
assert.match(css, /\.command-header\s*\{[^}]*display:\s*grid;/s, 'command header must be a stable grid');
assert.match(css, /\.session-chip\s*\{[^}]*white-space:\s*nowrap;/s, 'session chip text must not wrap');
assert.match(css, /@media\s*\(max-width:\s*720px\)/, 'mobile breakpoint is required');
assert.doesNotMatch(css, /border-radius:\s*(1[2-9]|[2-9][0-9])px/, 'cards and panels must not use oversized radii');
assert.doesNotMatch(css, /gradient|radial-gradient/, 'network console UI must not rely on decorative gradients');
```

- [ ] **Step 2: Run the failing CSS contract test**

Run:

```bash
node ansible_distribution_frontend/test/css_contract.test.mjs
```

Expected: fail because current CSS uses the old light login smoke UI tokens.

- [ ] **Step 3: Implement the approved visual system**

Replace `ansible_distribution_frontend/src/styles.css` with a network-console
stylesheet that includes these selectors:

```css
:root {
  color-scheme: dark;
  --background: #0f1720;
  --header: #101c27;
  --surface: #142230;
  --border: #253646;
  --muted-fill: #31505b;
  --accent: #7dd3c7;
  --warning: #f2c14e;
  --danger: #f97066;
  --text: #dce7e5;
  --muted: #93a4ad;
  font-family:
    Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI",
    sans-serif;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--background);
  color: var(--text);
}

[hidden] { display: none !important; }

.app-shell { min-height: 100vh; }

.command-header {
  display: grid;
  grid-template-columns: minmax(140px, 0.8fr) minmax(220px, 1fr) minmax(260px, auto);
  gap: 16px;
  align-items: center;
  padding: 14px 20px;
  border-bottom: 1px solid var(--border);
  background: var(--header);
}

.brand-lockup,
.command-nav a,
.header-action,
.panel-action,
.session-chip {
  min-height: 36px;
  border-radius: 8px;
  display: inline-flex;
  align-items: center;
  text-decoration: none;
}

.session-chip {
  gap: 8px;
  padding: 0 10px;
  border: 1px solid var(--border);
  color: var(--text);
  white-space: nowrap;
}

.session-chip strong { color: var(--accent); }

.forum-main {
  width: min(1120px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 28px 0 48px;
}

.page-panel {
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 18px;
  background: var(--surface);
}

.error-banner.is-warning { border-color: var(--warning); }
.error-banner.is-danger { border-color: var(--danger); }

@media (max-width: 720px) {
  .command-header {
    grid-template-columns: 1fr;
    align-items: stretch;
  }

  .command-context,
  .command-nav {
    overflow-x: auto;
  }
}
```

Keep the final CSS complete enough to style:

- `.command-context`
- `.route-title`
- `.board-directory`
- `.board-row`
- `.thread-list`
- `.challenge-card`
- `.scope-list`
- `.scope-chip`
- `.session-detail-grid`
- `.error-banner`
- `.empty-state`
- `button:focus-visible` and `a:focus-visible`

- [ ] **Step 4: Verify CSS contracts pass**

Run:

```bash
node ansible_distribution_frontend/test/css_contract.test.mjs
```

Expected: pass with `ok - hidden elements stay hidden` and no assertion errors.

- [ ] **Step 5: Commit Task 5**

Run:

```bash
git add ansible_distribution_frontend/src/styles.css ansible_distribution_frontend/test/css_contract.test.mjs
git commit -m "style(frontend): apply forum network console system"
```

## Task 6: End-To-End Fixture Verification

**Files:**

- Modify `ansible_distribution_frontend/test/integration_flow_harness.test.mjs`.
- Test all frontend tests.

- [ ] **Step 1: Add render assertions to the integration harness test**

Append these assertions to `ansible_distribution_frontend/test/integration_flow_harness.test.mjs`:

```js
import { renderAppShell } from '../src/forum_shell_renderer.mjs';
import { renderPageBody } from '../src/forum_page_renderers.mjs';

const renderedHome = renderAppShell({
  viewModel: publicHome.viewModel,
  bodyHtml: renderPageBody(publicHome.viewModel),
});
assert.match(renderedHome, /Local Forum Host/);
assert.match(renderedHome, /Anonymous/);
assert.match(renderedHome, /Browse boards/);

const renderedBoard = renderAppShell({
  viewModel: boardPage.viewModel,
  bodyHtml: renderPageBody(boardPage.viewModel),
});
assert.match(renderedBoard, /Self-custody DID/);
assert.match(renderedBoard, /New thread/);

const renderedInvalid = renderAppShell({
  viewModel: invalidState.viewModel,
  bodyHtml: renderPageBody(invalidState.viewModel),
});
assert.match(renderedInvalid, /Session unavailable/);
```

- [ ] **Step 2: Run the integration harness test**

Run:

```bash
node ansible_distribution_frontend/test/integration_flow_harness.test.mjs
```

Expected: pass and include the existing flow messages plus the new render
assertions.

- [ ] **Step 3: Run every frontend module test**

Run:

```bash
find ansible_distribution_frontend/test -name '*.test.mjs' -exec node {} \;
```

Expected: every test prints `ok - ...` and exits with status 0.

- [ ] **Step 4: Start a local static server for browser inspection**

Run:

```bash
python3 -m http.server 5173 -d ansible_distribution_frontend
```

Expected: server listens on port 5173. If 5173 is occupied, use 5174 and record
the port in the final implementation summary.

- [ ] **Step 5: Inspect the implemented UI in Browser**

Open:

```text
http://localhost:5173/#/
http://localhost:5173/#/boards
http://localhost:5173/#/boards/general
http://localhost:5173/#/login
http://localhost:5173/#/sessions
```

Check these points manually or with Browser screenshots:

- Header shows route title, navigation, and session chip.
- Home is a forum surface, not a login-only page.
- Boards and Board stay within current route skeleton.
- Login page is the dedicated challenge page.
- Sessions page shows trust tier, scopes, expiry, and revoke action when
  authenticated fixtures are wired in tests.
- Mobile width does not create horizontal overflow.

- [ ] **Step 6: Stop the static server**

Stop the `python3 -m http.server` process before ending the implementation
turn.

- [ ] **Step 7: Commit Task 6**

Run:

```bash
git add ansible_distribution_frontend/test/integration_flow_harness.test.mjs
git commit -m "test(frontend): cover rendered forum UI flows"
```

## Final Verification

Run:

```bash
find ansible_distribution_frontend/test -name '*.test.mjs' -exec node {} \;
git status --short
git log --oneline -6
```

Expected:

- All frontend tests pass.
- `git status --short` is clean.
- Recent commits show each completed task commit.

## Execution Notes

- Keep the current route skeleton exactly as defined in the design spec.
- Do not add new backend calls for this visual implementation pass.
- Keep app-mediated login copy explicit that the browser receives only a scoped
  relay session token.
- Use the fixtures and integration harness to cover anonymous, approved,
  rejected, expired, and invalid-session render states.
- If a renderer needs data that the view model does not expose, first extend the
  view model with a focused failing test instead of reaching into adapter
  internals from the renderer.
