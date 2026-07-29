import assert from 'node:assert/strict';

import { renderAppShell, renderCommandHeader } from '../src/forum_shell_renderer.mjs';
import { buildAppViewModel, PAGE_IDS } from '../src/state_model.mjs';
import { DEFAULT_SESSION_VIEW_MODEL } from '../src/session_lifecycle.mjs';
import { setCurrentLocale } from '../src/web_i18n.mjs';

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
assert.match(header, /Elix/);
assert.match(header, /Local Forum Host/);
assert.match(header, /class="elix-mark"/);
assert.match(header, /href="#\/boards"/);
assert.match(header, /href="#\/about"/);
assert.match(header, /匿名/);
assert.match(header, /登入/);
assert.match(header, /找人、找討論板、找關鍵字/);
assert.doesNotMatch(header, /class="header-action" href="#\/login"/);
assert.doesNotMatch(header, /class="session-chip is-anonymous" href="#\/login"/);
assert.doesNotMatch(header, /Anonymous|Login|Sign in|Diagnostics|Profile|Settings/);

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
  uiPreferences: {
    activeScene: 'forum',
    personalTheme: 'dark',
    forumTheme: 'light',
    motionMode: 'book',
  },
});
assert.match(shell, /自持有 DID/);
assert.match(shell, /新討論串/);
assert.match(shell, /data-active-scene="forum"/);
assert.match(shell, /data-personal-theme="dark"/);
assert.match(shell, /data-forum-theme="light"/);
assert.match(shell, /data-motion-mode="book"/);
assert.match(shell, /<section class="page-panel">Body<\/section>/);
assert.match(shell, /mobile-tabbar/);
assert.match(shell, /app-footer/);
assert.match(shell, /以身分支撐的社群 App/);
assert.match(shell, /href="\/privacy\?lang=zh-Hant"/);
assert.match(shell, /href="\/terms\?lang=zh-Hant"/);
assert.match(shell, /href="#\/about"/);

setCurrentLocale('en');
const englishShell = renderAppShell({
  viewModel: authenticatedVm,
  bodyHtml: '<section class="page-panel">Body</section>',
});
assert.match(englishShell, /identity-backed social app/);
assert.match(englishShell, /href="\/privacy\?lang=en"/);
assert.match(englishShell, /href="\/terms\?lang=en"/);
setCurrentLocale('zh-Hant');

const staleSessionsVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.sessions, params: {} },
  session: {
    authenticated: true,
    subjectDid: 'did:plc:fixtureabcdef',
    trustTier: 'self_custody_did',
    scopes: ['forum:post'],
    capabilities: { canRevoke: true },
  },
  forum: {
    capabilities: { canCreateThread: false, canReply: false },
  },
});
const sessionsShell = renderAppShell({
  viewModel: {
    ...staleSessionsVm,
    actions: {
      ...staleSessionsVm.actions,
      canCreateThread: true,
      canRevokeSession: true,
    },
  },
  bodyHtml: '<section class="page-panel">Sessions</section>',
});
assert.match(sessionsShell, /撤銷/);
assert.doesNotMatch(sessionsShell, /New thread|新討論串/);

const escaped = renderAppShell({
  viewModel: {
    ...anonymousVm,
    host: { displayName: '<script>alert(1)</script>' },
  },
  bodyHtml: '<p>Safe body</p>',
});
assert.doesNotMatch(escaped, /<script>/);
assert.match(escaped, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);

console.log('ok - forum shell renderer');
