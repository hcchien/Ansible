import { DEFAULT_SESSION_VIEW_MODEL } from './session_lifecycle.mjs';

export const PAGE_IDS = Object.freeze({
  home: 'home',
  boards: 'boards',
  board: 'board',
  sessions: 'sessions',
  login: 'login',
  notFound: 'not_found',
});

export function initialAppState() {
  return {
    route: { pageId: PAGE_IDS.home, params: {} },
    session: DEFAULT_SESSION_VIEW_MODEL,
    forum: null,
    loading: false,
    error: null,
    viewModel: buildAppViewModel({
      route: { pageId: PAGE_IDS.home, params: {} },
      session: DEFAULT_SESSION_VIEW_MODEL,
      forum: null,
    }),
  };
}

export function buildAppViewModel({
  route,
  session = DEFAULT_SESSION_VIEW_MODEL,
  forum = null,
  loading = false,
  error = null,
}) {
  return {
    page: pageDescriptor(route, forum),
    route,
    session,
    host: forum?.host ?? null,
    boards: forum?.boards ?? [],
    board: forum?.board ?? null,
    threads: forum?.threads ?? [],
    loading,
    error: error ?? forum?.error ?? session?.error ?? null,
    navigation: deriveNavigationItems(session),
    actions: {
      showLogin: !session?.authenticated,
      canCreateThread: Boolean(forum?.capabilities?.canCreateThread),
      canReply: Boolean(forum?.capabilities?.canReply),
      canRevokeSession: Boolean(session?.capabilities?.canRevoke),
    },
  };
}

export function deriveNavigationItems(session = DEFAULT_SESSION_VIEW_MODEL) {
  const items = [
    { id: PAGE_IDS.home, label: 'Feed', href: '#/' },
    { id: PAGE_IDS.boards, label: 'Boards', href: '#/boards' },
  ];

  if (session?.authenticated) {
    items.push({ id: PAGE_IDS.sessions, label: 'You', href: '#/sessions' });
  } else {
    items.push({ id: PAGE_IDS.login, label: 'Login', href: '#/login' });
  }

  return items;
}

function pageDescriptor(route, forum) {
  switch (route.pageId) {
    case PAGE_IDS.home:
      return {
        id: PAGE_IDS.home,
        title: 'Feed',
      };

    case PAGE_IDS.boards:
      return { id: PAGE_IDS.boards, title: 'Boards' };

    case PAGE_IDS.board:
      return {
        id: PAGE_IDS.board,
        title: forum?.board?.title || route.params?.boardId || 'Board',
      };

    case PAGE_IDS.sessions:
      return { id: PAGE_IDS.sessions, title: 'You' };

    case PAGE_IDS.login:
      return { id: PAGE_IDS.login, title: 'Login' };

    default:
      return { id: PAGE_IDS.notFound, title: 'Not found' };
  }
}
