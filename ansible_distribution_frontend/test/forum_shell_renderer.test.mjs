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
assert.match(header, /Elix/);
assert.match(header, /Local Forum Host/);
assert.match(header, /class="elix-mark"/);
assert.match(header, /href="#\/boards"/);
assert.match(header, /Anonymous/);
assert.match(header, /Login/);
assert.match(header, /找人、找討論板、找關鍵字/);
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
assert.match(shell, /mobile-tabbar/);
assert.match(shell, /app-footer/);
assert.match(shell, /identity-backed social app/);

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
assert.match(sessionsShell, /Revoke/);
assert.doesNotMatch(sessionsShell, /New thread/);

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
