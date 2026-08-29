import {
  createHostedWebThread,
  createWebDeliberation,
  fetchBoardDeliberation,
  fetchBoardDeliberations,
  fetchBoardModerationState,
  fetchForumHostInfo,
  fetchHostedBoards,
  submitBoardPollVote,
  submitWebDeliberationStatement,
  submitWebDeliberationVote,
  fetchWebDeliberationResponses,
  withdrawWebDeliberationVote,
  requestWebDeliberationExport,
  fetchWebModerationActions,
  fetchWebModerationReports,
  submitWebModerationAction,
  submitWebReport,
} from './forum_host_client.mjs';
import {
  fetchAuthorTimeline,
  fetchBoardExternalContent,
  fetchBoardFeed,
  fetchPublicProfile,
  fetchThreadFeed,
} from './appview_client.mjs';
import {
  createWebNotificationReadStore,
  projectWebReplyNotifications,
} from './web_notifications.mjs';
import {
  createPasskeySignedOperation,
  createPasskeySignedThread,
} from './web_publication_client.mjs';
import { ERROR_TYPES, normalizeFrontendError, notFoundError, scopeError } from './error_taxonomy.mjs';
import {
  applyModerationStateToThreads,
  groupReportsByBoard,
  normalizeModerationAction,
  normalizeModerationState,
  normalizeReport,
  validateReportDraft,
} from './moderation_model.mjs';
import { createRelayApiClient } from './relay_api_client.mjs';

const PROHIBITED_CREDENTIAL_CLAIMS = new Set([
  'nationalid',
  'legalname',
  'birthdate',
  'documentnumber',
  'passportnumber',
  'nationalidhash',
  'passportnumberhash',
  'rawproviderassertion',
]);

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
    submitBoardPollVote,
    fetchBoardDeliberations,
    fetchBoardDeliberation,
    createWebDeliberation,
    submitWebDeliberationStatement,
    submitWebDeliberationVote,
    fetchWebDeliberationResponses,
    withdrawWebDeliberationVote,
    requestWebDeliberationExport,
  },
  webPublicationClient = { createPasskeySignedThread, createPasskeySignedOperation },
  appViewClient = {
    fetchAuthorTimeline,
    fetchBoardExternalContent,
    fetchBoardFeed,
    fetchPublicProfile,
    fetchThreadFeed,
  },
}) {
  const notificationReadStore = createWebNotificationReadStore({ storage });
  const publicHandleCache = new Map();

  async function loadForumHome({ sessionViewModel, includePublicFeed = false } = {}) {
    const [host, boardsResponse] = await Promise.all([
      forumHostClient.fetchForumHostInfo({ relayBaseUrl, fetchImpl }),
      forumHostClient.fetchHostedBoards({ relayBaseUrl, fetchImpl }),
    ]);

    const home = buildForumHomeViewModel({
      host,
      boards: boardsResponse.boards ?? [],
      sessionViewModel,
    });

    if (!includePublicFeed) return home;

    const readableBoards = home.boards.filter(isAnonymousReadableBoard);
    const feedResults = await Promise.all(
      readableBoards.map(async (board) => {
        try {
          const response = await appViewClient.fetchBoardFeed({
            appViewBaseUrl,
            fetchImpl,
            boardId: board.id,
          });
          return { board, items: response?.items ?? [], unavailable: false };
        } catch {
          return { board, items: [], unavailable: true };
        }
      }),
    );

    const threads = feedResults
      .flatMap(({ board, items }) =>
        buildThreadsFromFeed(items).map((thread) => ({
          ...thread,
          boardId: board.id,
          boardSlug: board.slug || board.id,
          boardTitle: board.title || board.slug || board.id,
        })),
      )
      .sort(compareThreadsNewestFirst);

    await fillMissingAuthorHandles(threads);

    return {
      ...home,
      publicFeed: {
        threads,
        unavailable: feedResults.some((result) => result.unavailable),
      },
    };
  }

  async function loadProfilePage({ did, sessionViewModel } = {}) {
    const identity = String(did ?? '').trim();
    const home = await loadForumHome({ sessionViewModel });
    const [profileResult, timelineResult] = await Promise.allSettled([
      appViewClient.fetchPublicProfile({
        appViewBaseUrl,
        fetchImpl,
        did: identity,
      }),
      appViewClient.fetchAuthorTimeline({
        appViewBaseUrl,
        fetchImpl,
        did: identity,
        limit: 100,
      }),
    ]);

    const profile = profileResult.status === 'fulfilled'
      ? normalizePublicProfile(profileResult.value, identity)
      : {
          did: identity,
          handle: null,
          displayName: null,
          bio: null,
          reputationTier: 'basic',
          missing: true,
          unavailable: profileResult.reason?.status !== 404,
        };
    const profilePosts = timelineResult.status === 'fulfilled'
      ? buildPublicProfileEntries(timelineResult.value?.items ?? [])
      : [];

    return {
      ...home,
      profile,
      profilePosts,
      profilePostsUnavailable: timelineResult.status === 'rejected',
      error: null,
    };
  }

  async function loadBoardPage({ boardId, sessionViewModel } = {}) {
    const home = await loadForumHome({ sessionViewModel });
    const board = home.boards.find((candidate) => boardMatchesRoute(candidate, boardId));

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

    const [moderationState, externalContent, feedResponse, deliberationsResponse] = await Promise.all([
      loadPublicModerationState(board.id),
      loadBoardExternalContent(board),
      loadBoardFeed(board.id),
      loadBoardDeliberations(board.id),
    ]);

    const rawThreads = buildThreadsFromFeed(feedResponse?.items ?? []);
    await fillMissingAuthorHandles(rawThreads);

    return {
      ...home,
      board,
      threads: applyModerationStateToThreads(rawThreads, moderationState),
      deliberations: (deliberationsResponse?.deliberations ?? []).map(normalizeDeliberation),
      moderationState,
      externalContent,
      error: null,
    };
  }

  async function loadDeliberationPage({ boardId, deliberationId, sessionViewModel } = {}) {
    const boardPage = await loadBoardPage({ boardId, sessionViewModel });
    if (boardPage.board?.missing) {
      return { ...boardPage, deliberation: null };
    }
    try {
      const response = await forumHostClient.fetchBoardDeliberation({
        relayBaseUrl,
        fetchImpl,
        boardId: boardPage.board.id,
        deliberationId,
      });
      let viewerResponses = {};
      if (
        sessionViewModel?.authenticated &&
        typeof forumHostClient.fetchWebDeliberationResponses === 'function'
      ) {
        const own = await forumHostClient.fetchWebDeliberationResponses({
          relayBaseUrl,
          storage,
          fetchImpl,
          boardId: boardPage.board.id,
          deliberationId,
        });
        viewerResponses = own?.responses ?? {};
      }
      return {
        ...boardPage,
        deliberation: {
          ...normalizeDeliberation(response?.deliberation),
          viewerResponses,
        },
        error: null,
      };
    } catch (error) {
      return {
        ...boardPage,
        deliberation: null,
        error: normalizeFrontendError(error),
      };
    }
  }

  async function loadBoardDeliberations(boardId) {
    if (typeof forumHostClient.fetchBoardDeliberations !== 'function') {
      return { deliberations: [] };
    }
    try {
      return await forumHostClient.fetchBoardDeliberations({
        relayBaseUrl,
        fetchImpl,
        boardId,
      });
    } catch {
      return { deliberations: [], unavailable: true };
    }
  }

  async function loadThreadPage({ boardId, threadId, sessionViewModel } = {}) {
    const home = await loadForumHome({ sessionViewModel });
    const board = home.boards.find((candidate) => boardMatchesRoute(candidate, boardId));

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
        thread: null,
        threads: [],
        moderationState: normalizeModerationState(null),
        error: notFoundError('board_not_found', { boardId }),
      };
    }

    const [moderationState, threadFeedResponse] = await Promise.all([
      loadPublicModerationState(board.id),
      loadThreadFeed(threadId),
    ]);
    const threads = applyModerationStateToThreads(
      buildThreadsFromFeed(threadFeedResponse?.items ?? []),
      moderationState,
    );
    await fillMissingAuthorHandles(threads);
    const thread = threads.find((candidate) => candidate.id === threadId) ?? null;

    return {
      ...home,
      board,
      thread,
      threads,
      moderationState,
      externalContent: null,
      error: thread ? null : notFoundError('thread_not_found', { boardId, threadId }),
    };
  }

  async function loadBoardFeed(boardId) {
    if (typeof appViewClient.fetchBoardFeed !== 'function') {
      return { items: [] };
    }

    try {
      return await appViewClient.fetchBoardFeed({
        appViewBaseUrl,
        fetchImpl,
        boardId,
      });
    } catch {
      return { items: [] };
    }
  }

  async function loadThreadFeed(threadId) {
    if (typeof appViewClient.fetchThreadFeed !== 'function') {
      return { items: [] };
    }

    try {
      return await appViewClient.fetchThreadFeed({
        appViewBaseUrl,
        fetchImpl,
        threadId,
      });
    } catch {
      return { items: [] };
    }
  }

  // AppView profiles carry display names and handles when a public profile op
  // exists. A Relay-registered handle is also public, stable DID anchor data,
  // however, and older accounts may have one without a profile op. Resolve it
  // only as a presentation fallback; it never changes the author DID or any
  // authorization decision.
  async function fillMissingAuthorHandles(threads) {
    const authors = [];
    for (const thread of threads) {
      authors.push(thread, ...(thread.posts ?? []));
    }

    await Promise.all(
      authors.map(async (author) => {
        if (author?.authorHandle || !String(author?.authorDid ?? '').startsWith('did:')) return;
        const handle = await resolveRelayHandle(author.authorDid);
        if (handle) author.authorHandle = handle;
      }),
    );
  }

  async function resolveRelayHandle(did) {
    const identity = String(did ?? '').trim();
    if (!identity.startsWith('did:')) return null;
    if (!publicHandleCache.has(identity)) {
      const request = createRelayApiClient({ relayBaseUrl, fetchImpl })
        .getJson(`/api/v1/identity/handle/${encodeURIComponent(identity)}`)
        .then((response) => String(response?.handle ?? '').trim() || null)
        .catch(() => null);
      publicHandleCache.set(identity, request);
    }
    return publicHandleCache.get(identity);
  }

  async function loadNotifications({ sessionViewModel, boards = null } = {}) {
    const subjectDid = sessionViewModel?.subjectDid;
    if (!sessionViewModel?.authenticated || !subjectDid) {
      return { items: [], unreadCount: 0 };
    }

    let availableBoards = boards;
    if (!Array.isArray(availableBoards)) {
      const response = await forumHostClient.fetchHostedBoards({
        relayBaseUrl,
        fetchImpl,
      });
      availableBoards = (response?.boards ?? []).map(normalizeHostedBoard);
    }

    const feeds = await Promise.all(
      availableBoards.map(async (board) => ({
        boardId: board.id,
        ...(await loadBoardFeed(board.id)),
      })),
    );
    const subjectDids = [
      subjectDid,
      ...(sessionViewModel.identityAliases ?? []),
    ];
    const items = projectWebReplyNotifications({
      feeds,
      subjectDids,
      readIds: notificationReadStore.readIds(subjectDid),
    });
    return {
      items,
      unreadCount: items.filter((item) => !item.isRead).length,
    };
  }

  function markNotificationRead({ sessionViewModel, notificationId }) {
    if (!sessionViewModel?.subjectDid || !notificationId) return;
    notificationReadStore.markRead(sessionViewModel.subjectDid, notificationId);
  }

  function markAllNotificationsRead({ sessionViewModel, notificationIds }) {
    if (!sessionViewModel?.subjectDid) return;
    notificationReadStore.markAllRead(
      sessionViewModel.subjectDid,
      notificationIds ?? [],
    );
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

  async function submitThreadDraft({ title, boardId, poll = null, sessionViewModel }) {
    if (!sessionViewModel?.capabilities?.canPost) {
      throw scopeError('forum:post');
    }

    if (
      typeof forumHostClient.fetchForumHostInfo !== 'function' &&
      typeof forumHostClient.createHostedWebThread === 'function'
    ) {
      const legacyFixtureResponse = await forumHostClient.createHostedWebThread({
        relayBaseUrl,
        storage,
        fetchImpl,
        boardId,
        title,
      });
      return normalizeThreadSubmission(legacyFixtureResponse);
    }

    const [host, boardsResponse] = await Promise.all([
      forumHostClient.fetchForumHostInfo({ relayBaseUrl, fetchImpl }),
      forumHostClient.fetchHostedBoards({ relayBaseUrl, fetchImpl }),
    ]);
    const boards = boardsResponse.boards ?? [];
    const selectedBoardId =
      boardId ??
      (String(boards[0]?.board_id ?? boards[0]?.hosted_board_id ?? '') || null);
    const board = boards.find(
      (candidate) =>
        String(candidate.board_id ?? candidate.hosted_board_id ?? '') === selectedBoardId,
    );
    if (!board) throw notFoundError('board_not_found', { boardId: selectedBoardId });

    const publisher =
      forumHostClient.createPasskeySignedThread ??
      webPublicationClient.createPasskeySignedThread;
    const response = await publisher({
      relayBaseUrl,
      storage,
      fetchImpl,
      authorDid: sessionViewModel.subjectDid,
      targetForumHost:
        host.canonical_base_url ?? host.base_url ?? relayBaseUrl,
      boardId: String(board.board_id ?? board.hosted_board_id),
      boardPolicyVersion: board.access_policy_version ?? 1,
      title,
      poll,
    });

    return normalizeThreadSubmission(response);
  }

  async function submitPollVote({ boardId, pollId, optionId, sessionViewModel }) {
    if (!sessionViewModel?.capabilities?.canPost) throw scopeError('forum:post');
    if (typeof forumHostClient.submitBoardPollVote !== 'function') {
      throw notFoundError('poll_not_found', { boardId, pollId });
    }
    return forumHostClient.submitBoardPollVote({
      relayBaseUrl, storage, fetchImpl, boardId, pollId, optionId,
    });
  }

  async function submitDeliberationDraft({
    boardId,
    title,
    prompt,
    exportMode,
    sessionViewModel,
  }) {
    if (!sessionViewModel?.capabilities?.canPost) throw scopeError('forum:post');
    return forumHostClient.createWebDeliberation({
      relayBaseUrl,
      storage,
      fetchImpl,
      boardId,
      title,
      prompt,
      exportMode,
    });
  }

  async function submitDeliberationStatement({
    boardId,
    deliberationId,
    text,
    sessionViewModel,
  }) {
    if (!sessionViewModel?.capabilities?.canPost) throw scopeError('forum:post');
    return forumHostClient.submitWebDeliberationStatement({
      relayBaseUrl,
      storage,
      fetchImpl,
      boardId,
      deliberationId,
      text,
    });
  }

  async function submitDeliberationVote({
    boardId,
    deliberationId,
    statementId,
    stance,
    supersedesIntentId = null,
    sessionViewModel,
  }) {
    if (!sessionViewModel?.capabilities?.canPost) throw scopeError('forum:post');
    return forumHostClient.submitWebDeliberationVote({
      relayBaseUrl,
      storage,
      fetchImpl,
      boardId,
      deliberationId,
      statementId,
      stance,
      supersedesIntentId,
    });
  }

  async function exportDeliberation({
    boardId,
    deliberationId,
    view = 'aggregates',
    sessionViewModel,
  }) {
    if (!sessionViewModel?.authenticated) throw scopeError('forum:read');
    return forumHostClient.requestWebDeliberationExport({
      relayBaseUrl,
      storage,
      fetchImpl,
      boardId,
      deliberationId,
      view,
    });
  }

  async function withdrawDeliberationVote({
    boardId,
    deliberationId,
    statementId,
    supersedesIntentId,
    sessionViewModel,
  }) {
    if (!sessionViewModel?.capabilities?.canPost) throw scopeError('forum:post');
    if (!supersedesIntentId) throw notFoundError('deliberation_response_not_found');
    return forumHostClient.withdrawWebDeliberationVote({
      relayBaseUrl,
      storage,
      fetchImpl,
      boardId,
      deliberationId,
      statementId,
      supersedesIntentId,
    });
  }

  async function submitContentMutation({
    action,
    entityType,
    entityId,
    boardId,
    expectedPreviousRevision,
    payload,
    sessionViewModel,
  }) {
    const requiredCapability =
      action === 'forum.edit' ? 'canEdit' : 'canDelete';
    if (!sessionViewModel?.capabilities?.[requiredCapability]) {
      throw scopeError(action === 'forum.edit' ? 'forum:edit' : 'forum:delete');
    }

    const [host, boardsResponse] = await Promise.all([
      forumHostClient.fetchForumHostInfo({ relayBaseUrl, fetchImpl }),
      forumHostClient.fetchHostedBoards({ relayBaseUrl, fetchImpl }),
    ]);
    const board = (boardsResponse.boards ?? []).find(
      (candidate) =>
        String(candidate.board_id ?? candidate.hosted_board_id ?? '') ===
        String(boardId),
    );
    if (!board) throw notFoundError('board_not_found', { boardId });

    const publisher =
      forumHostClient.createPasskeySignedOperation ??
      webPublicationClient.createPasskeySignedOperation;
    return publisher({
      relayBaseUrl,
      storage,
      fetchImpl,
      authorDid: sessionViewModel.subjectDid,
      targetForumHost: host.canonical_base_url ?? host.base_url ?? relayBaseUrl,
      boardId: String(board.board_id ?? board.hosted_board_id),
      boardPolicyVersion: board.access_policy_version ?? 1,
      action,
      entityType,
      entityId,
      expectedPreviousRevision,
      payload,
    });
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
    loadProfilePage,
    loadBoardPage,
    loadDeliberationPage,
    loadThreadPage,
    loadNotifications,
    markNotificationRead,
    markAllNotificationsRead,
    submitThreadDraft,
    submitPollVote,
    submitDeliberationDraft,
    submitDeliberationStatement,
    submitDeliberationVote,
    withdrawDeliberationVote,
    exportDeliberation,
    submitContentMutation,
    submitReport,
    loadModerationConsole,
    submitModerationAction,
  };
}

function normalizeDeliberation(raw) {
  if (!raw || typeof raw !== 'object') return null;
  return {
    ...raw,
    id: String(raw.id ?? ''),
    boardId: String(raw.board_id ?? raw.boardId ?? ''),
    exportMode: raw.export_mode ?? raw.exportMode ?? 'aggregates_only',
    statementCount: Number(raw.statement_count ?? raw.statementCount ?? 0),
    participantCount: Number(raw.participant_count ?? raw.participantCount ?? 0),
    statements: Array.isArray(raw.statements)
      ? raw.statements.map((statement) => ({
          ...statement,
          id: String(statement.id ?? ''),
          text: String(statement.text ?? ''),
        }))
      : [],
    report: raw.report && typeof raw.report === 'object' ? raw.report : null,
  };
}

function normalizePublicProfile(raw, fallbackDid) {
  return {
    did: String(raw?.did ?? fallbackDid ?? '').trim(),
    handle: cleanPublicText(raw?.handle),
    displayName: cleanPublicText(raw?.display_name ?? raw?.displayName),
    bio: cleanPublicText(raw?.bio),
    avatarUrl: cleanPublicText(raw?.avatar_url ?? raw?.avatarUrl),
    reputationTier: cleanPublicText(
      raw?.reputation_tier ?? raw?.reputationTier,
    ) ?? 'basic',
    publicCredentials: Array.isArray(raw?.public_credentials)
      ? raw.public_credentials.map(normalizePublicCredential).filter(Boolean)
      : [],
    missing: false,
    unavailable: false,
  };
}

function normalizePublicCredential(raw) {
  const credentialType = cleanPublicText(raw?.credential_type ?? raw?.credentialType);
  const issuerDid = cleanPublicText(raw?.issuer_did ?? raw?.issuerDid);
  const badge = cleanPublicText(raw?.badge);
  const value = cleanPublicText(raw?.value);
  const validUntil = cleanPublicText(raw?.valid_until ?? raw?.validUntil);
  if (!credentialType || !issuerDid || !badge || !value) return null;
  return { credentialType, issuerDid, badge, value, validUntil };
}

export function buildPublicProfileEntries(items = []) {
  const publicItems = items.filter((item) => {
    const visibility = String(item?.visibility ?? 'public').trim().toLowerCase();
    return visibility === '' || visibility === 'public';
  });
  const threads = new Map(
    publicItems
      .filter((item) => item?.entity_type === 'thread' || item?.entityType === 'thread')
      .map((item) => [String(item.entity_id ?? item.entityId ?? ''), item]),
  );
  const entries = new Map();

  for (const item of publicItems) {
    const type = item?.entity_type ?? item?.entityType;
    const id = String(item?.entity_id ?? item?.entityId ?? '').trim();
    if (!id) continue;
    const payload = item?.payload && typeof item.payload === 'object' ? item.payload : {};

    if (type === 'post') {
      if (cleanPublicText(payload.parentPostId ?? payload.parent_post_id)) continue;
      const threadId = cleanPublicText(
        item.thread_id ?? item.threadId ?? payload.threadId ?? payload.thread_id,
      );
      const boardId = cleanPublicText(
        item.board_id ?? item.boardId ?? payload.boardId ?? payload.board_id,
      );
      if (!threadId || !boardId) continue;
      const thread = threads.get(threadId);
      const threadPayload = thread?.payload ?? {};
      entries.set(`thread:${threadId}`, profileEntry(item, {
        id,
        type: 'discussion',
        title: cleanPublicText(
          payload.title ?? payload.threadTitle ?? threadPayload.title,
        ),
        body: cleanPublicText(
          payload.content ?? threadPayload.description,
        ) ?? '',
        boardId,
        threadId,
        createdAt: item.created_at ?? item.createdAt ?? thread?.created_at ?? thread?.createdAt,
      }));
      continue;
    }

    if (type === 'thread') {
      const threadId = id;
      if (!entries.has(`thread:${threadId}`)) {
        entries.set(`thread:${threadId}`, profileEntry(item, {
          id,
          type: 'discussion',
          title: cleanPublicText(payload.title),
          body: cleanPublicText(payload.description) ?? '',
          boardId: cleanPublicText(
            item.board_id ?? item.boardId ?? payload.boardId ?? payload.board_id,
          ),
          threadId,
          createdAt: item.created_at ?? item.createdAt,
        }));
      }
      continue;
    }

    if (type === 'note' || type === 'murmur') {
      entries.set(`${type}:${id}`, profileEntry(item, {
        id,
        type,
        title: cleanPublicText(payload.title),
        body: cleanPublicText(payload.body) ?? '',
        boardId: null,
        threadId: null,
        createdAt: item.created_at ?? item.createdAt,
      }));
    }
  }

  return [...entries.values()].sort((a, b) => {
    const aTime = Date.parse(a.createdAt ?? '') || 0;
    const bTime = Date.parse(b.createdAt ?? '') || 0;
    return bTime - aTime;
  });
}

function profileEntry(item, entry) {
  return {
    ...entry,
    authorDid: cleanPublicText(item.author_did ?? item.authorDid),
    authorHandle: cleanPublicText(item.author_handle ?? item.authorHandle),
    authorDisplayName: cleanPublicText(
      item.author_display_name ?? item.authorDisplayName,
    ),
    reputationTier: cleanPublicText(
      item.reputation_tier ?? item.reputationTier,
    ) ?? 'basic',
  };
}

function cleanPublicText(value) {
  const text = String(value ?? '').trim();
  return text || null;
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
  const accessPolicy = board?.access_policy ?? {};
  const postRequirement = accessPolicy?.post?.requirement ?? 'posting_policy';
  const requirement =
    postRequirement !== 'public' &&
    postRequirement !== 'posting_policy' &&
    postRequirement !== 'board_moderator'
      ? accessPolicy?.requirements?.[postRequirement] ?? null
      : null;

  return {
    // `board_id` is the host-scoped canonical sequence ID. Slugs are display
    // aliases only and must never become publication or routing identities.
    id: String(board?.board_id ?? board?.hosted_board_id ?? ''),
    legacyHostedBoardId: board?.hosted_board_id ?? '',
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
    accessPolicy: {
      version: accessPolicy.version ?? 1,
      readRequirement: accessPolicy?.read?.requirement ?? 'public',
      postRequirement,
      contentVisibility: accessPolicy.content_visibility ?? 'public',
      federation: accessPolicy.federation ?? 'enabled',
      credentialRequirement: requirement
        ? {
            name: postRequirement,
            credentialType: requirement.credential_type ?? '',
            credentialConfigurationId:
              requirement.credential_configuration_id ?? null,
            trustedIssuers: Array.isArray(requirement.trusted_issuers)
              ? requirement.trusted_issuers.filter((value) => typeof value === 'string')
              : [],
            claims: Array.isArray(requirement.claims)
              ? requirement.claims
                  .filter((claim) => claim && typeof claim === 'object')
                  .filter((claim) => !isProhibitedCredentialClaim(claim.path))
                  .map((claim) => ({
                    path: claim.path ?? '',
                    op: claim.op ?? '',
                    value: claim.value ?? '',
                  }))
              : [],
            holderBindingRequired: requirement.holder_binding === 'required',
            statusRequired: requirement.status?.required === true,
          }
        : null,
    },
  };
}

function isAnonymousReadableBoard(board) {
  return (
    board?.permissions?.canRead === true &&
    board?.accessPolicy?.contentVisibility === 'public' &&
    board?.accessPolicy?.readRequirement === 'public'
  );
}

function compareThreadsNewestFirst(left, right) {
  const leftTime = Date.parse(left?.updatedAt ?? left?.createdAt ?? '') || 0;
  const rightTime = Date.parse(right?.updatedAt ?? right?.createdAt ?? '') || 0;
  return rightTime - leftTime;
}

function isProhibitedCredentialClaim(path) {
  const normalized = String(path ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return PROHIBITED_CREDENTIAL_CLAIMS.has(normalized);
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
  const publication = response?.publication ?? null;
  return {
    accepted: Boolean(response?.accepted),
    subjectDid: publication?.author_did ?? response?.subject_did ?? null,
    trustTier: response?.trust_tier ?? null,
    ...(publication
      ? {
          operationId: publication.operation_id ?? null,
          operationHash: publication.operation_hash ?? null,
          authorProofScheme: publication.author_proof?.scheme ?? null,
        }
      : {}),
  };
}

export function buildThreadsFromFeed(items) {
  const threadsById = new Map();
  const postsByThread = new Map();
  const activeReactions = new Map();

  // Board feeds are newest-first, while a state projection needs to see an
  // insert before a later update/delete. Items without a log id retain their
  // incoming order for compatibility with older AppViews.
  const orderedItems = [...items].sort((left, right) => {
    const leftLogId = Number(left?.log_id);
    const rightLogId = Number(right?.log_id);
    if (Number.isFinite(leftLogId) && Number.isFinite(rightLogId)) return leftLogId - rightLogId;
    return 0;
  });

  for (const item of orderedItems) {
    if (item.entity_type === 'thread' && item.op_type === 'insert') {
      const payload = item.payload ?? {};
      threadsById.set(item.entity_id, {
        id: item.entity_id,
        title: payload.title || '',
        poll: normalizePoll(payload.poll),
        boardId: item.board_id || payload.boardId || payload.board_id || '',
        authorDid: item.author_did,
        authorDisplayName: normalizeAuthorDisplayName(item, payload),
        authorHandle: normalizeAuthorHandle(item, payload),
        updatedAt: item.created_at,
        replyCount: 0,
        posts: [],
        revision: item.op_id ?? String(item.log_id ?? ''),
      });
    } else if (item.entity_type === 'thread' && item.op_type === 'update') {
      const thread = threadsById.get(item.entity_id);
      if (thread) {
        const payload = item.payload ?? {};
        if (typeof payload.title === 'string') thread.title = payload.title;
        thread.updatedAt = item.created_at ?? thread.updatedAt;
        thread.revision = item.op_id ?? String(item.log_id ?? thread.revision);
      }
    } else if (item.entity_type === 'thread' && item.op_type === 'delete') {
      threadsById.delete(item.entity_id);
      postsByThread.delete(item.entity_id);
    } else if (item.entity_type === 'post' && item.op_type === 'insert') {
      const payload = item.payload ?? {};
      const threadId = payload.threadId || payload.thread_id;
      if (threadId) {
        if (!postsByThread.has(threadId)) {
          postsByThread.set(threadId, []);
        }
        postsByThread.get(threadId).push({
          id: item.entity_id,
          content: payload.content || '',
          authorDid: item.author_did,
          authorDisplayName: normalizeAuthorDisplayName(item, payload),
          authorHandle: normalizeAuthorHandle(item, payload),
          createdAt: item.created_at,
          revision: item.op_id ?? String(item.log_id ?? ''),
        });
      }
    } else if (
      item.entity_type === 'post' &&
      (item.op_type === 'update' || item.op_type === 'delete')
    ) {
      for (const posts of postsByThread.values()) {
        const index = posts.findIndex((post) => post.id === item.entity_id);
        if (index < 0) continue;
        if (item.op_type === 'delete') {
          posts.splice(index, 1);
        } else {
          const payload = item.payload ?? {};
          posts[index] = {
            ...posts[index],
            content: payload.content ?? payload.newContent ?? posts[index].content,
            updatedAt: item.created_at ?? posts[index].updatedAt,
            revision: item.op_id ?? String(item.log_id ?? posts[index].revision),
          };
        }
        break;
      }
    } else if (item.entity_type === 'reaction') {
      const payload = item.payload ?? {};
      const targetType = String(payload.targetType ?? '').toLowerCase();
      const targetId = String(payload.targetId ?? '').trim();
      if (!targetId || !['thread', 'post'].includes(targetType)) continue;

      if (item.op_type === 'delete') {
        activeReactions.delete(item.entity_id);
      } else if (item.op_type === 'insert' || item.op_type === 'update') {
        // Relay enforces one active reaction per author/target and updates keep
        // the entity id stable, so replacing this entry avoids double-counting.
        activeReactions.set(item.entity_id, { targetType, targetId });
      }
    }
  }

  const threads = [...threadsById.values()];
  for (const thread of threads) {
    const posts = postsByThread.get(thread.id) ?? [];
    posts.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
    thread.posts = posts;
    thread.replyCount = posts.length;
    if (posts.length > 0) {
      thread.updatedAt = posts[posts.length - 1].createdAt;
    }
  }

  const threadById = new Map(threads.map((thread) => [thread.id, thread]));
  const postById = new Map();
  for (const thread of threads) {
    for (const post of thread.posts) postById.set(post.id, post);
  }
  for (const reaction of activeReactions.values()) {
    const target = reaction.targetType === 'thread'
      ? threadById.get(reaction.targetId)
      : postById.get(reaction.targetId);
    if (target) target.likeCount = (target.likeCount ?? 0) + 1;
  }

  threads.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));

  return threads;
}

function normalizePoll(poll) {
  if (!poll || !Array.isArray(poll.options) || poll.options.length < 2) return null;
  const options = poll.options
    .filter((option) => option && typeof option.id === 'string' && typeof option.label === 'string')
    .map((option) => ({ id: option.id, label: option.label, votes: Number(option.votes ?? 0) || 0 }));
  return options.length >= 2 ? { options, closesAt: poll.closes_at ?? null } : null;
}

function normalizeAuthorHandle(item, payload = {}) {
  const value =
    item?.author_handle ??
    item?.authorHandle ??
    payload?.author_handle ??
    payload?.authorHandle ??
    payload?.handle ??
    null;
  const handle = String(value ?? '').trim();
  return handle || null;
}

function normalizeAuthorDisplayName(item, payload = {}) {
  const value =
    item?.author_display_name ??
    item?.authorDisplayName ??
    payload?.author_display_name ??
    payload?.authorDisplayName ??
    payload?.display_name ??
    payload?.displayName ??
    null;
  const displayName = String(value ?? '').trim();
  return displayName || null;
}

function boardMatchesRoute(board, routeBoardId) {
  const requested = String(routeBoardId ?? '');
  return [board?.id, board?.slug, board?.legacyHostedBoardId]
    .map((value) => String(value ?? ''))
    .includes(requested);
}
