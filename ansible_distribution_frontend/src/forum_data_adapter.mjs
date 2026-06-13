import {
  createHostedWebThread,
  fetchBoardModerationState,
  fetchForumHostInfo,
  fetchHostedBoards,
  fetchWebModerationActions,
  fetchWebModerationReports,
  submitWebModerationAction,
  submitWebReport,
} from './forum_host_client.mjs';
import { fetchBoardExternalContent } from './appview_client.mjs';
import { ERROR_TYPES, normalizeFrontendError, notFoundError, scopeError } from './error_taxonomy.mjs';
import {
  applyModerationStateToThreads,
  groupReportsByBoard,
  normalizeModerationAction,
  normalizeModerationState,
  normalizeReport,
  validateReportDraft,
} from './moderation_model.mjs';

export function createForumDataAdapter({
  relayBaseUrl,
  // The AppView is a separate read service; external/federated content is
  // surfaced only through it. Defaults to the relay base URL so dev works
  // out of the box, but production points it at the AppView origin.
  appViewBaseUrl = relayBaseUrl,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
  forumHostClient = {
    fetchForumHostInfo,
    fetchHostedBoards,
    createHostedWebThread,
    submitWebReport,
    fetchWebModerationReports,
    fetchWebModerationActions,
    submitWebModerationAction,
    fetchBoardModerationState,
  },
  appViewClient = { fetchBoardExternalContent },
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
        moderationState: normalizeModerationState(null),
        error: notFoundError('board_not_found', { boardId }),
      };
    }

    const [moderationState, externalContent] = await Promise.all([
      loadPublicModerationState(board.id),
      loadBoardExternalContent(board),
    ]);

    return {
      ...home,
      board,
      threads: applyModerationStateToThreads([], moderationState),
      moderationState,
      externalContent,
      error: null,
    };
  }

  // External (federated) content is fetched ONLY when the board host opted in
  // via posting_policy.external_inclusion. Anonymous public web has no per-user
  // opt-in, so the board opt-in is the sole gate here. The AppView is a separate
  // service and may be down — a failure degrades to an empty external section
  // and must never take the board page down (constitution Base Rule 6 spirit:
  // a public read failing closed-but-renderable, never a hard error).
  async function loadBoardExternalContent(board) {
    if (board?.postingPolicy?.externalInclusion !== true) {
      return null;
    }

    if (typeof appViewClient.fetchBoardExternalContent !== 'function') {
      return { items: [], unavailable: true };
    }

    try {
      const response = await appViewClient.fetchBoardExternalContent({
        appViewBaseUrl,
        fetchImpl,
        boardId: board.id,
      });
      return {
        items: (response?.items ?? []).map(normalizeExternalItem),
        nextCursor: response?.next_cursor ?? null,
        hasMore: Boolean(response?.has_more),
        unavailable: false,
      };
    } catch {
      return { items: [], unavailable: true };
    }
  }

  // The moderation-state endpoint is public and reason-coded by design
  // (constitution Base Rule 6); a failure must not take the board page down.
  async function loadPublicModerationState(boardId) {
    if (typeof forumHostClient.fetchBoardModerationState !== 'function') {
      return normalizeModerationState(null);
    }

    try {
      const state = await forumHostClient.fetchBoardModerationState({
        relayBaseUrl,
        fetchImpl,
        boardId,
      });
      return normalizeModerationState(state);
    } catch {
      return normalizeModerationState(null);
    }
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

  // POST /web/reports. Validates the draft locally first (mirrors the relay
  // rule set) so the picker can fail fast, then submits over the cookie rail.
  async function submitReport({
    targetKind,
    targetRef,
    boardId,
    reasonCode,
    note,
    sessionViewModel,
  }) {
    if (!sessionViewModel?.authenticated) {
      throw signInRequiredError();
    }

    const draftError = validateReportDraft({ reasonCode, note });
    if (draftError) {
      throw draftError;
    }

    const { report, duplicate } = await forumHostClient.submitWebReport({
      relayBaseUrl,
      storage,
      fetchImpl,
      targetKind,
      targetRef,
      boardId,
      reasonCode,
      note: String(note ?? '').trim() || null,
    });

    return { report: normalizeReport(report), duplicate: Boolean(duplicate) };
  }

  // Loads the moderator console: open reports grouped by board + the audit
  // trail. A relay 403 not_board_moderator becomes a renderable console state
  // instead of a thrown error.
  async function loadModerationConsole({ sessionViewModel } = {}) {
    if (!sessionViewModel?.authenticated) {
      return {
        moderation: {
          status: 'signed_out',
          reportGroups: [],
          auditActions: [],
          error: null,
        },
      };
    }

    try {
      const [reportsResponse, actionsResponse] = await Promise.all([
        forumHostClient.fetchWebModerationReports({
          relayBaseUrl,
          storage,
          fetchImpl,
          status: 'open',
        }),
        forumHostClient.fetchWebModerationActions({
          relayBaseUrl,
          storage,
          fetchImpl,
        }),
      ]);

      return {
        moderation: {
          status: 'moderator',
          reportGroups: groupReportsByBoard(
            (reportsResponse?.reports ?? []).map(normalizeReport),
          ),
          auditActions: (actionsResponse?.actions ?? []).map(
            normalizeModerationAction,
          ),
          error: null,
        },
      };
    } catch (error) {
      const semanticError = normalizeFrontendError(error);

      if (semanticError.type === ERROR_TYPES.notBoardModerator) {
        return {
          moderation: {
            status: 'not_moderator',
            reportGroups: [],
            auditActions: [],
            error: semanticError,
          },
        };
      }

      throw error;
    }
  }

  // POST /web/moderation/actions — every action is reason-coded and lands in
  // the audit trail relay-side.
  async function submitModerationAction({
    action,
    targetRef,
    boardId,
    reasonCode,
    reportId,
  }) {
    const response = await forumHostClient.submitWebModerationAction({
      relayBaseUrl,
      storage,
      fetchImpl,
      action,
      targetRef,
      boardId,
      reasonCode,
      reportId: reportId ?? null,
    });

    return normalizeModerationAction(response?.action);
  }

  return {
    loadForumHome,
    loadBoardPage,
    submitThreadDraft,
    submitReport,
    loadModerationConsole,
    submitModerationAction,
  };
}

function signInRequiredError() {
  return {
    type: ERROR_TYPES.unauthenticated,
    message: 'sign_in_required',
    retryable: false,
    code: 'sign_in_required',
    detail: undefined,
  };
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
  const postingPolicy = board?.posting_policy ?? {};

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
    postingPolicy: {
      minPostTier: postingPolicy.min_post_tier ?? null,
      // 4a placed the host's external-content opt-in inside posting_policy.
      // Mutually exclusive with min_post_tier (enforced relay-side); this flag
      // is the public-web gate for surfacing curated federated content.
      externalInclusion: postingPolicy.external_inclusion === true,
    },
  };
}

// Normalizes an AppView external item into a UI-ready record. External content
// is NEVER verified Elix content: it carries a fixed external_unverified tier,
// a visible origin (instance + actor), and a compliance level. We coerce the
// compliance level to the known enum (compatible/unknown) and default unknown.
export function normalizeExternalItem(item) {
  const compliance = item?.compliance_level === 'compatible' ? 'compatible' : 'unknown';

  return {
    id: item?.log_id ?? item?.op_id ?? '',
    opId: item?.op_id ?? null,
    boardId: item?.board_id ?? '',
    content: item?.content ?? '',
    createdAt: item?.created_at ?? null,
    actorUri: item?.external_actor_uri ?? '',
    instance: item?.external_instance ?? '',
    complianceLevel: compliance,
    reputationTier: item?.reputation_tier ?? 'external_unverified',
    origin: item?.origin ?? 'activitypub',
    external: true,
  };
}

export function normalizeThreadSubmission(response) {
  return {
    accepted: Boolean(response?.accepted),
    subjectDid: response?.subject_did ?? null,
    trustTier: response?.trust_tier ?? null,
  };
}
