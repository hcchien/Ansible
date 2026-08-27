import { DEFAULT_SESSION_VIEW_MODEL } from './session_lifecycle.mjs';
import { t } from './web_i18n.mjs';

export const PAGE_IDS = Object.freeze({
  home: 'home',
  boards: 'boards',
  board: 'board',
  thread: 'thread',
  profile: 'profile',
  notifications: 'notifications',
  sessions: 'sessions',
  login: 'login',
  moderation: 'moderation',
  faq: 'faq',
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
    thread: forum?.thread ?? null,
    threads: forum?.threads ?? [],
    profile: forum?.profile ?? null,
    profilePosts: forum?.profilePosts ?? [],
    profilePostsUnavailable: Boolean(forum?.profilePostsUnavailable),
    publicFeed: forum?.publicFeed ?? null,
    notifications: forum?.notifications ?? { items: [], unreadCount: 0 },
    externalContent: forum?.externalContent ?? null,
    moderation: forum?.moderation ?? null,
    moderationState: forum?.moderationState ?? null,
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
    { id: PAGE_IDS.home, label: t('common.feed'), href: '#/' },
    { id: PAGE_IDS.boards, label: t('common.boards'), href: '#/boards' },
    { id: PAGE_IDS.faq, label: t('common.aboutElix'), href: '#/about' },
  ];

  if (session?.authenticated) {
    items.push({
      id: PAGE_IDS.notifications,
      label: t('home.notifications'),
      href: '#/notifications',
    });
    items.push({
      id: PAGE_IDS.moderation,
      label: t('common.moderation'),
      href: '#/moderation',
    });
    items.push({ id: PAGE_IDS.sessions, label: t('common.you'), href: '#/sessions' });
  } else {
    items.push({ id: PAGE_IDS.login, label: t('common.login'), href: '#/login' });
  }

  return items;
}

function pageDescriptor(route, forum) {
  switch (route.pageId) {
    case PAGE_IDS.home:
      return {
        id: PAGE_IDS.home,
        title: t('common.feed'),
      };

    case PAGE_IDS.boards:
      return { id: PAGE_IDS.boards, title: t('common.boards') };

    case PAGE_IDS.board:
      return {
        id: PAGE_IDS.board,
        title: forum?.board?.title || route.params?.boardId || t('common.board'),
      };

    case PAGE_IDS.thread:
      return {
        id: PAGE_IDS.thread,
        title: forum?.thread?.title || route.params?.threadId || t('common.threadFallback'),
      };

    case PAGE_IDS.profile:
      return {
        id: PAGE_IDS.profile,
        title:
          forum?.profile?.displayName ||
          forum?.profile?.handle ||
          route.params?.did ||
          t('profile.title'),
      };

    case PAGE_IDS.sessions:
      return { id: PAGE_IDS.sessions, title: t('common.you') };

    case PAGE_IDS.notifications:
      return { id: PAGE_IDS.notifications, title: t('home.notifications') };

    case PAGE_IDS.login:
      return { id: PAGE_IDS.login, title: t('common.login') };

    case PAGE_IDS.moderation:
      return { id: PAGE_IDS.moderation, title: t('common.moderation') };

    case PAGE_IDS.faq:
      return { id: PAGE_IDS.faq, title: t('common.aboutElix') };

    default:
      return { id: PAGE_IDS.notFound, title: t('common.notFound') };
  }
}
