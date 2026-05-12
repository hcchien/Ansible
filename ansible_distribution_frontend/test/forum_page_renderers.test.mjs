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
assert.match(homeHtml, /唯讀/);
assert.match(homeHtml, /Elix 是重視身分的社群 App/);
assert.match(homeHtml, /RELAY · BOARD · #general/);
assert.match(homeHtml, /打開看板/);
assert.match(homeHtml, /Note/);
assert.match(homeHtml, /登入後可簽署發文/);
assert.match(homeHtml, /class="cols social-home"/);
assert.match(homeHtml, /class="compose"/);
assert.match(homeHtml, /已訂閱看板/);
assert.doesNotMatch(homeHtml, /工作階段/);
assert.doesNotMatch(homeHtml, /RELAY · 來源/);
assert.doesNotMatch(homeHtml, /Relay 資料/);
assert.doesNotMatch(homeHtml, /Miki Chen|Ting Wang|24 people follow you|FROM A FOLLOW/);
assert.doesNotMatch(homeHtml, /App-approved web session login|Read only|Open board|Login required for signed posting/);

const boardHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'approvedDid',
});
const boardState = await runBoardRouteFlow(boardHarness);
const boardHtml = renderPageBody(boardState.viewModel);
assert.match(boardHtml, /General/);
assert.match(boardHtml, /新討論串/);
assert.match(boardHtml, /自持有 DID/);
assert.match(boardHtml, /class="board-head"/);
assert.match(boardHtml, /class="card thread-list"/);
assert.match(boardHtml, /BOARD ACTIVITY/);
assert.doesNotMatch(boardHtml, /New thread|Sign in to post|Self-custody DID/);

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
assert.match(loginHtml, /用 Elix app 登入/);
assert.match(loginHtml, /wsc_fixture/);
assert.match(loginHtml, /發布討論串/);
assert.match(loginHtml, /class="login-grid"/);
assert.match(loginHtml, /class="challenge-payload-preview"/);
assert.match(loginHtml, /class="qr-code"/);
assert.match(loginHtml, /data-action="poll-login"/);
assert.doesNotMatch(loginHtml, /data-action="start-login"/);
assert.match(loginHtml, /身分留在 Elix app/);
assert.match(loginHtml, /用 Elix app 掃描/);
assert.match(loginHtml, /用 Elix app 掃描這個 QR code/);
assert.doesNotMatch(loginHtml, /登入挑戰|建立挑戰|有效挑戰|The key stays|Approving the challenge|App login challenge|Create challenge|Start app login/);
assert.doesNotMatch(loginHtml, /Deep link/);
assert.doesNotMatch(loginHtml, /QR payload/);
assert.doesNotMatch(loginHtml, /trisaura:\/\/web-session\/approve/);
assert.doesNotMatch(loginHtml, /Open in app/);

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
assert.doesNotMatch(unsafeLoginHtml, /href="#"/);
assert.doesNotMatch(unsafeLoginHtml, /javascript:alert\(1\)/);

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
assert.match(sessionsHtml, /自持有 DID/);
assert.match(sessionsHtml, /發布討論串/);
assert.match(sessionsHtml, /撤銷目前工作階段/);
assert.match(sessionsHtml, /class="card sessions-page"/);
assert.match(sessionsHtml, /這個瀏覽器工作階段有權限範圍/);
assert.doesNotMatch(sessionsHtml, /Revoke current session|This browser session is scoped and revocable|Trust tier|Expiry/);

const notFoundVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.notFound, params: { path: '/missing' } },
  session: { authenticated: false },
  forum: null,
});
assert.match(renderPageBody(notFoundVm), /路徑不可用/);
assert.doesNotThrow(() => renderPageBody(undefined));
assert.match(renderPageBody(undefined), /路徑不可用/);

console.log('ok - forum page renderers');
