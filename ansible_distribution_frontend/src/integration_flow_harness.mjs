import { createForumDataAdapter } from './forum_data_adapter.mjs';
import { createPageController } from './page_routes.mjs';
import { createSessionLifecycle } from './session_lifecycle.mjs';
import {
  createFixtureForumHostClient,
  createFixtureStorage,
  createFixtureWebSessionClient,
} from './contract_fixtures.mjs';

export function createFrontendFlowHarness({
  routeHash = '#/',
  sessionMode = 'anonymous',
  challengeStatus = 'approved',
  relayBaseUrl = 'http://localhost:4001',
  webOrigin = 'http://localhost:5173',
} = {}) {
  const storage = createFixtureStorage({
    token: sessionMode === 'anonymous' ? undefined : tokenForSessionMode(sessionMode),
  });
  const webSessionClient = createFixtureWebSessionClient({
    sessionMode: sessionMode === 'anonymous' ? 'invalid' : sessionMode,
    challengeStatus,
  });
  const forumHostClient = createFixtureForumHostClient();
  const sessionLifecycle = createSessionLifecycle({
    relayBaseUrl,
    webOrigin,
    storage,
    webSessionClient,
  });
  const forumDataAdapter = createForumDataAdapter({
    relayBaseUrl,
    storage,
    forumHostClient,
  });
  const pageController = createPageController({
    getCurrentHash: () => routeHash,
    sessionLifecycle,
    forumDataAdapter,
  });

  return {
    relayBaseUrl,
    webOrigin,
    routeHash,
    storage,
    webSessionClient,
    forumHostClient,
    sessionLifecycle,
    forumDataAdapter,
    pageController,
  };
}

export async function runPublicHomeFlow(harness) {
  return harness.pageController.loadCurrentRoute();
}

export async function runBoardRouteFlow(harness) {
  return harness.pageController.loadCurrentRoute();
}

export async function runApprovedLoginFlow(harness) {
  await harness.sessionLifecycle.startAppLogin();
  return harness.sessionLifecycle.pollLoginChallenge();
}

export async function runInvalidSessionRestoreFlow(harness) {
  return harness.pageController.loadCurrentRoute();
}

export async function runThreadDraftFlow(harness, { title }) {
  const sessionState = await harness.sessionLifecycle.restore();

  return harness.forumDataAdapter.submitThreadDraft({
    title,
    sessionViewModel: sessionState.viewModel,
  });
}

function tokenForSessionMode(sessionMode) {
  if (sessionMode === 'invalid') {
    return 'wst_invalid';
  }

  if (sessionMode === 'expired') {
    return 'wst_expired';
  }

  return 'wst_fixture';
}
