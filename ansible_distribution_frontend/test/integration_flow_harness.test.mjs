import assert from 'node:assert/strict';

import {
  createFrontendFlowHarness,
  runApprovedLoginFlow,
  runBoardRouteFlow,
  runInvalidSessionRestoreFlow,
  runPublicHomeFlow,
  runThreadDraftFlow,
} from '../src/integration_flow_harness.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';
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
console.log('ok - runs authenticated board route flow');

const loginHarness = createFrontendFlowHarness({
  routeHash: '#/login',
  sessionMode: 'anonymous',
  challengeStatus: 'approved',
});
const loginState = await runApprovedLoginFlow(loginHarness);
assert.equal(loginState.status, 'authenticated');
assert.equal(loginState.viewModel.trustTier, 'self_custody_did');
assert.equal(loginHarness.storage.getItem(WEB_SESSION_TOKEN_KEY), 'wst_fixture');
console.log('ok - runs app-approved login flow');

const invalidHarness = createFrontendFlowHarness({
  routeHash: '#/',
  sessionMode: 'invalid',
});
const invalidState = await runInvalidSessionRestoreFlow(invalidHarness);
assert.equal(invalidState.session.error.type, ERROR_TYPES.unauthenticated);
assert.equal(invalidHarness.storage.getItem(WEB_SESSION_TOKEN_KEY), null);
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
    assert.equal(error.type, ERROR_TYPES.missingScope);
    assert.equal(error.detail.requiredScope, 'forum:post');
    return true;
  },
);
console.log('ok - runs missing-scope thread draft flow');
