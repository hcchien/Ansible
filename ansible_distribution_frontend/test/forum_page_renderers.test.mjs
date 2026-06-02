import assert from 'node:assert/strict';

import { renderPageBody } from '../src/forum_page_renderers.mjs';
import {
  createFrontendFlowHarness,
  runBoardRouteFlow,
  runPublicHomeFlow,
} from '../src/integration_flow_harness.mjs';
import { PAGE_IDS, buildAppViewModel } from '../src/state_model.mjs';
import { setCurrentLocale } from '../src/web_i18n.mjs';

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
assert.match(homeHtml, /class="cols social-home mobile-focus-home"/);
assert.match(homeHtml, /class="mobile-focus-stage"/);
assert.match(homeHtml, /data-scene="personal"/);
assert.match(homeHtml, /個人版/);
assert.match(homeHtml, /討論區/);
assert.match(homeHtml, /MURMUR · 0:38/);
assert.match(homeHtml, /AI · 橫向橋/);
assert.match(homeHtml, /往左滑/);
assert.match(homeHtml, /class="mobile-compose-fab"/);
assert.match(homeHtml, /已訂閱看板/);
assert.doesNotMatch(homeHtml, /工作階段/);
assert.doesNotMatch(homeHtml, /RELAY · 來源/);
assert.doesNotMatch(homeHtml, /Relay 資料/);
assert.doesNotMatch(homeHtml, /傳給圈內/);
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
assert.match(sessionsHtml, /class="settings-home"/);
assert.match(sessionsHtml, /本機身分/);
assert.match(sessionsHtml, /身分與裝置/);
assert.match(sessionsHtml, /日常/);
assert.match(sessionsHtml, /邊界/);
assert.match(sessionsHtml, /介面與語言/);
assert.match(sessionsHtml, /每版的光/);
assert.match(sessionsHtml, /換版的動態/);
assert.match(sessionsHtml, /data-action="set-scene-theme"/);
assert.match(sessionsHtml, /data-action="set-motion-mode"/);
assert.match(sessionsHtml, /未設/);
assert.doesNotMatch(sessionsHtml, /Revoke current session|This browser session is scoped and revocable|Trust tier|Expiry/);

setCurrentLocale('en');

const englishHomeHtml = renderPageBody(homeState.viewModel);
assert.match(englishHomeHtml, /Your Notes and Murmurs/);
assert.match(englishHomeHtml, /Swipe left/);
assert.match(englishHomeHtml, /Forum/);
assert.match(englishHomeHtml, /From past murmurs/);
assert.match(englishHomeHtml, /Resonate/);
assert.doesNotMatch(englishHomeHtml, /個人版|討論區|往左滑|橫向橋|共鳴/);

const englishSessionsHtml = renderPageBody(sessionsVm);
assert.match(englishSessionsHtml, /Done/);
assert.match(englishSessionsHtml, /Local identity/);
assert.match(englishSessionsHtml, /Identity and devices/);
assert.match(englishSessionsHtml, /Interface and language/);
assert.match(englishSessionsHtml, /Local-first/);
assert.match(englishSessionsHtml, /Not set/);
assert.doesNotMatch(englishSessionsHtml, /完成|本機身分|身分與裝置|介面與語言|本地優先|未設/);

setCurrentLocale('zh-Hant');

const notFoundVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.notFound, params: { path: '/missing' } },
  session: { authenticated: false },
  forum: null,
});
assert.match(renderPageBody(notFoundVm), /路徑不可用/);
assert.doesNotThrow(() => renderPageBody(undefined));
assert.match(renderPageBody(undefined), /路徑不可用/);

console.log('ok - forum page renderers');
