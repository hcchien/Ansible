import assert from 'node:assert/strict';

import { renderPageBody } from '../src/forum_page_renderers.mjs';
import {
  createFrontendFlowHarness,
  runBoardRouteFlow,
  runPublicHomeFlow,
} from '../src/integration_flow_harness.mjs';
import { PAGE_IDS, buildAppViewModel } from '../src/state_model.mjs';

const homeHarness = createFrontendFlowHarness({ routeHash: '#/', sessionMode: 'anonymous' });
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

const unsafeLoginHtml = renderPageBody(loginVm, {
  login: {
    status: 'pending',
    challenge: {
      challengeId: 'wsc_unsafe',
      expiresAt: '2026-05-12T01:00:00Z',
      deepLink: 'javascript:alert(1)',
      qrPayload: 'javascript:alert(1)',
    },
    requestedScopes: ['forum:read'],
  },
});
assert.doesNotMatch(unsafeLoginHtml, /href="javascript:alert\(1\)"/);
assert.match(unsafeLoginHtml, /href="#"/);
assert.match(unsafeLoginHtml, />javascript:alert\(1\)<\/a>/);

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
assert.doesNotThrow(() => renderPageBody(undefined));
assert.match(renderPageBody(undefined), /Route unavailable/);

console.log('ok - forum page renderers');
