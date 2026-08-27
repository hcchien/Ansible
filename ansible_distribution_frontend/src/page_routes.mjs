import { buildAppViewModel, initialAppState, PAGE_IDS } from './state_model.mjs';
import { DEFAULT_SESSION_VIEW_MODEL } from './session_lifecycle.mjs';

export function parseRoute(hash) {
  const path = normalizeHashPath(hash);
  const segments = path.split('/').filter(Boolean).map(decodeURIComponent);

  if (segments.length === 0) {
    return { pageId: PAGE_IDS.home, params: {} };
  }

  if (segments.length === 1 && segments[0] === 'boards') {
    return { pageId: PAGE_IDS.boards, params: {} };
  }

  if (segments.length === 2 && segments[0] === 'boards') {
    return { pageId: PAGE_IDS.board, params: { boardId: segments[1] } };
  }

  if (segments.length === 4 && segments[0] === 'boards' && segments[2] === 'threads') {
    return {
      pageId: PAGE_IDS.thread,
      params: { boardId: segments[1], threadId: segments[3] },
    };
  }

  if (segments.length === 2 && segments[0] === 'profiles') {
    return { pageId: PAGE_IDS.profile, params: { did: segments[1] } };
  }

  if (segments.length === 1 && segments[0] === 'sessions') {
    return { pageId: PAGE_IDS.sessions, params: {} };
  }

  if (segments.length === 1 && segments[0] === 'notifications') {
    return { pageId: PAGE_IDS.notifications, params: {} };
  }

  if (segments.length === 1 && segments[0] === 'login') {
    return { pageId: PAGE_IDS.login, params: {} };
  }

  if (segments.length === 1 && segments[0] === 'moderation') {
    return { pageId: PAGE_IDS.moderation, params: {} };
  }

  if (segments.length === 1 && segments[0] === 'about') {
    return { pageId: PAGE_IDS.faq, params: {} };
  }

  return { pageId: PAGE_IDS.home, params: { recoveredFrom: path } };
}

export function routeToHash(route) {
  switch (route.pageId) {
    case PAGE_IDS.home:
      return '#/';

    case PAGE_IDS.boards:
      return '#/boards';

    case PAGE_IDS.board:
      return `#/boards/${encodeURIComponent(route.params.boardId)}`;

    case PAGE_IDS.thread:
      return `#/boards/${encodeURIComponent(route.params.boardId)}/threads/${encodeURIComponent(route.params.threadId)}`;

    case PAGE_IDS.profile:
      return `#/profiles/${encodeURIComponent(route.params.did)}`;

    case PAGE_IDS.sessions:
      return '#/sessions';

    case PAGE_IDS.notifications:
      return '#/notifications';

    case PAGE_IDS.login:
      return '#/login';

    case PAGE_IDS.moderation:
      return '#/moderation';

    case PAGE_IDS.faq:
      return '#/about';

    default:
      return '#/404';
  }
}

export function createPageController({
  getCurrentHash = () => globalThis.location?.hash ?? '#/',
  sessionLifecycle,
  forumDataAdapter,
}) {
  let state = initialAppState();

  async function loadCurrentRoute() {
    return loadRoute(parseRoute(getCurrentHash()));
  }

  async function loadRoute(route) {
    if (route.pageId === PAGE_IDS.login) {
      return setState(route, DEFAULT_SESSION_VIEW_MODEL, null);
    }

    const sessionState = await sessionLifecycle.restore();
    const session = sessionState.viewModel;

    if (route.pageId === PAGE_IDS.faq) {
      return setStateWithNotifications(route, session, null);
    }

    if (route.pageId === PAGE_IDS.home || route.pageId === PAGE_IDS.boards) {
      const forum = await forumDataAdapter.loadForumHome({
        sessionViewModel: session,
        includePublicFeed: route.pageId === PAGE_IDS.home,
      });
      return setStateWithNotifications(route, session, forum);
    }

    if (route.pageId === PAGE_IDS.board) {
      const forum = await forumDataAdapter.loadBoardPage({
        boardId: route.params.boardId,
        sessionViewModel: session,
      });
      return setStateWithNotifications(route, session, forum);
    }

    if (route.pageId === PAGE_IDS.thread) {
      const forum = await forumDataAdapter.loadThreadPage({
        boardId: route.params.boardId,
        threadId: route.params.threadId,
        sessionViewModel: session,
      });
      return setStateWithNotifications(route, session, forum);
    }

    if (route.pageId === PAGE_IDS.profile) {
      const forum = await forumDataAdapter.loadProfilePage({
        did: route.params.did,
        sessionViewModel: session,
      });
      return setStateWithNotifications(route, session, forum);
    }

    if (route.pageId === PAGE_IDS.moderation) {
      const forum = await forumDataAdapter.loadModerationConsole({
        sessionViewModel: session,
      });
      return setStateWithNotifications(route, session, forum);
    }

    if (route.pageId === PAGE_IDS.notifications) {
      const forum = await forumDataAdapter.loadForumHome({
        sessionViewModel: session,
      });
      return setStateWithNotifications(route, session, forum);
    }

    return setStateWithNotifications(route, session, null);
  }

  async function setStateWithNotifications(route, session, forum) {
    if (
      session?.authenticated &&
      typeof forumDataAdapter.loadNotifications === 'function'
    ) {
      const notifications = await forumDataAdapter.loadNotifications({
        sessionViewModel: session,
        boards: forum?.boards ?? null,
      });
      forum = { ...(forum ?? {}), notifications };
    }
    return setState(route, session, forum);
  }

  function getState() {
    return state;
  }

  function setState(route, session, forum) {
    state = {
      route,
      session,
      forum,
      loading: false,
      error: forum?.error ?? session?.error ?? null,
      viewModel: buildAppViewModel({ route, session, forum }),
    };

    return state;
  }

  return { loadCurrentRoute, loadRoute, getState };
}

function normalizeHashPath(hash) {
  const value = hash || '#/';
  const withoutHash = value.startsWith('#') ? value.slice(1) : value;
  const path = withoutHash.startsWith('/') ? withoutHash : `/${withoutHash}`;
  return path.replace(/\/+$/, '') || '/';
}
