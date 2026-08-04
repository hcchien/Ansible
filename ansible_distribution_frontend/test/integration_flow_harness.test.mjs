import assert from 'node:assert/strict';

import {
  createFrontendFlowHarness,
  runApprovedLoginFlow,
  runBoardRouteFlow,
  runInvalidSessionRestoreFlow,
  runPublicHomeFlow,
  runThreadDraftFlow,
} from '../src/integration_flow_harness.mjs';
import { renderAppShell } from '../src/forum_shell_renderer.mjs';
import { renderPageBody } from '../src/forum_page_renderers.mjs';
import { PAGE_IDS } from '../src/state_model.mjs';
import { WEB_SESSION_TOKEN_KEY } from '../src/web_session_client.mjs';

const publicHarness = createFrontendFlowHarness({
  routeHash: '#/',
  sessionMode: 'anonymous',
});
const publicHome = await runPublicHomeFlow(publicHarness);
assert.equal(publicHome.route.pageId, PAGE_IDS.home);
assert.equal(publicHome.session.authenticated, false);
assert.equal(publicHome.viewModel.actions.showLogin, true);
assert.equal(publicHome.viewModel.boards[0].id, 'general');
const renderedHome = renderAppShell({
  viewModel: publicHome.viewModel,
  bodyHtml: renderPageBody(publicHome.viewModel),
});
assert.match(renderedHome, /Local Forum Host/);
assert.match(renderedHome, /匿名/);
// The feed opens straight into the stream, so the session state reaches the
// visitor through the header pill rather than a blurb above the posts.
assert.match(renderedHome, /唯讀/);
assert.match(renderedHome, /RELAY · BOARD · #general/);
assert.doesNotMatch(renderedHome, /Anonymous|Read only|Sign in|Open board/);
console.log('ok - runs public home flow');

const boardHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'approvedDid',
});
const boardPage = await runBoardRouteFlow(boardHarness);
assert.equal(boardPage.route.pageId, PAGE_IDS.board);
assert.equal(boardPage.session.trustTier, 'self_custody_did');
assert.equal(boardPage.viewModel.page.title, 'General');
assert.equal(boardPage.viewModel.actions.canCreateThread, true);
const renderedBoard = renderAppShell({
  viewModel: boardPage.viewModel,
  bodyHtml: renderPageBody(boardPage.viewModel),
});
assert.match(renderedBoard, /自持有 DID/);
assert.match(renderedBoard, /新討論串/);
assert.doesNotMatch(renderedBoard, /Self-custody DID|New thread|Sign in to post/);
console.log('ok - runs authenticated board route flow');

const loginHarness = createFrontendFlowHarness({
  routeHash: '#/login',
  sessionMode: 'anonymous',
  challengeStatus: 'approved',
});
const loginState = await runApprovedLoginFlow(loginHarness);
assert.equal(loginState.status, 'authenticated');
assert.equal(loginState.viewModel.trustTier, 'self_custody_did');
assert.equal(loginHarness.storage.getItem(WEB_SESSION_TOKEN_KEY), null);
console.log('ok - runs app-approved login flow');

const invalidHarness = createFrontendFlowHarness({
  routeHash: '#/',
  sessionMode: 'invalid',
});
const invalidState = await runInvalidSessionRestoreFlow(invalidHarness);
assert.equal(invalidState.session.authenticated, false);
assert.equal(invalidHarness.storage.getItem(WEB_SESSION_TOKEN_KEY), null);
const renderedInvalid = renderAppShell({
  viewModel: invalidState.viewModel,
  bodyHtml: renderPageBody(invalidState.viewModel),
});
assert.match(renderedInvalid, /匿名/);
console.log('ok - runs invalid session restore flow');

const draftHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'approvedDid',
});
const acceptedDraft = await runThreadDraftFlow(draftHarness, {
  title: 'Fixture thread',
});
assert.deepEqual(acceptedDraft, {
  accepted: true,
  subjectDid: 'did:plc:fixture',
  trustTier: 'self_custody_did',
});
console.log('ok - runs accepted thread draft flow');

const blockedHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'anonymous',
});
await assert.rejects(
  () => runThreadDraftFlow(blockedHarness, { title: 'Blocked draft' }),
  (error) => {
    assert.equal(error.type, 'missing_scope');
    assert.equal(error.detail.requiredScope, 'forum:post');
    return true;
  },
);
console.log('ok - runs missing-scope thread draft flow');
