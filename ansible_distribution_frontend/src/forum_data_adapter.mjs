import {
  createHostedWebThread,
  fetchForumHostInfo,
  fetchHostedBoards,
} from './forum_host_client.mjs';
import { notFoundError, scopeError } from './error_taxonomy.mjs';

export function createForumDataAdapter({
  relayBaseUrl,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
  forumHostClient = {
    fetchForumHostInfo,
    fetchHostedBoards,
    createHostedWebThread,
  },
}) {
  async function loadForumHome({ sessionViewModel } = {}) {
    const [host, boardsResponse] = await Promise.all([
      forumHostClient.fetchForumHostInfo({ relayBaseUrl, fetchImpl }),
      forumHostClient.fetchHostedBoards({ relayBaseUrl, fetchImpl }),
    ]);

    return buildForumHomeViewModel({
      host,
      boards: boardsResponse.boards ?? [],
      sessionViewModel,
    });
  }

  async function loadBoardPage({ boardId, sessionViewModel } = {}) {
    const home = await loadForumHome({ sessionViewModel });
    const board = home.boards.find(
      (candidate) => candidate.id === boardId || candidate.slug === boardId,
    );

    if (!board) {
      return {
        ...home,
        board: {
          id: boardId,
          slug: boardId,
          title: boardId,
          description: null,
          missing: true,
        },
        threads: [],
        error: notFoundError('board_not_found', { boardId }),
      };
    }

    return {
      ...home,
      board,
      threads: [],
      error: null,
    };
  }

  async function submitThreadDraft({ title, sessionViewModel }) {
    if (!sessionViewModel?.capabilities?.canPost) {
      throw scopeError('forum:post');
    }

    const response = await forumHostClient.createHostedWebThread({
      relayBaseUrl,
      storage,
      fetchImpl,
      title,
    });

    return normalizeThreadSubmission(response);
  }

  return { loadForumHome, loadBoardPage, submitThreadDraft };
}

export function buildForumHomeViewModel({
  host,
  boards,
  sessionViewModel = {},
}) {
  const normalizedBoards = boards.map(normalizeHostedBoard);

  return {
    host: normalizeForumHost(host),
    boards: normalizedBoards,
    primaryBoardId: normalizedBoards[0]?.id ?? null,
    capabilities: {
      canCreateThread: Boolean(
        host?.capabilities?.create_threads &&
          sessionViewModel?.capabilities?.canPost,
      ),
      canReply: Boolean(sessionViewModel?.capabilities?.canReply),
    },
    trustTier: sessionViewModel?.trustTier ?? 'anonymous',
  };
}

export function normalizeForumHost(host) {
  return {
    id: host?.forum_host_id ?? '',
    displayName: host?.display_name ?? '',
    capabilities: {
      createThreads: Boolean(host?.capabilities?.create_threads),
    },
  };
}

export function normalizeHostedBoard(board) {
  const permissions = board?.permissions ?? {};

  return {
    id: board?.hosted_board_id ?? '',
    slug: board?.slug ?? board?.hosted_board_id ?? '',
    title: board?.title ?? '',
    description: board?.description ?? '',
    canonicalUri: board?.canonical_board_uri ?? '',
    permissions: {
      canRead: permissions.read !== false,
      canWrite: Boolean(permissions.write),
    },
  };
}

export function normalizeThreadSubmission(response) {
  return {
    accepted: Boolean(response?.accepted),
    subjectDid: response?.subject_did ?? null,
    trustTier: response?.trust_tier ?? null,
  };
}
