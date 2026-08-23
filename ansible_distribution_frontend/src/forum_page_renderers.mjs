import { PAGE_IDS } from './state_model.mjs';
import {
  describeError,
  formatExpiry,
  formatScope,
  moderationActionLabel,
  reasonCodeLabel,
  shortIdentity,
  targetKindLabel,
  trustTierLabel,
} from './forum_ui_text.mjs';
import { escapeHtml } from './forum_shell_renderer.mjs';
import { icon, sealIcon } from './icons.mjs';
import {
  REPORT_REASON_CODES,
  actionsForTargetKind,
} from './moderation_model.mjs';
import { renderQrCodeSvg } from './qr_code.mjs';
import {
  LOCALE_NATIVE_NAMES,
  SUPPORTED_LOCALES,
  getCurrentLocale,
  t,
} from './web_i18n.mjs';
import { TRUST_TIERS, meetsMinPostTier } from './web_session_client.mjs';
import { renderElixFaq } from './faq_page.mjs';

export function renderPageBody(viewModel, uiState = {}) {
  const pageId = viewModel?.page?.id ?? viewModel?.route?.pageId;
  let bodyHtml;

  switch (pageId) {
    case PAGE_IDS.home:
      bodyHtml = renderHome(viewModel, uiState);
      break;
    case PAGE_IDS.boards:
      bodyHtml = renderBoards(viewModel);
      break;
    case PAGE_IDS.board:
      bodyHtml = renderBoard(viewModel, uiState);
      break;
    case PAGE_IDS.thread:
      bodyHtml = renderThreadDetail(viewModel, uiState);
      break;
    case PAGE_IDS.login:
      bodyHtml = renderLogin(viewModel, uiState.login ?? {});
      break;
    case PAGE_IDS.sessions:
      bodyHtml = renderSessions(viewModel, uiState);
      break;
    case PAGE_IDS.notifications:
      bodyHtml = renderNotifications(viewModel);
      break;
    case PAGE_IDS.moderation:
      bodyHtml = renderModeration(viewModel, uiState);
      break;
    case PAGE_IDS.faq:
      bodyHtml = renderElixFaq();
      break;
    default:
      bodyHtml = renderNotFound(viewModel);
  }

  return `${renderThreadDraftForm(uiState.threadDraft)}${bodyHtml}`;
}

function renderNotifications(viewModel) {
  const notifications = viewModel.notifications?.items ?? [];
  const hasUnread = notifications.some((notification) => !notification.isRead);
  return `
    <section class="cols" aria-labelledby="notifications-title">
      ${renderLeftRail(viewModel, 'notifications')}
      <section class="feed notifications-page" aria-labelledby="notifications-title">
        <div class="feed-head notifications-head">
          <div>
            <p class="section-label">${escapeHtml(t('notifications.kicker'))}</p>
            <h1 id="notifications-title">${escapeHtml(t('notifications.title'))}</h1>
            <p>${escapeHtml(t('notifications.localOnly'))}</p>
          </div>
          ${hasUnread ? `<button class="secondary-action" type="button" data-action="mark-all-notifications-read">${escapeHtml(t('notifications.markAllRead'))}</button>` : ''}
        </div>
        <section class="card notification-list">
          ${notifications.length === 0 ? `<p class="notification-empty">${escapeHtml(t('notifications.empty'))}</p>` : notifications.map(renderNotificationRow).join('')}
        </section>
      </section>
      ${renderRightRail(viewModel, viewModel.boards ?? [])}
    </section>
  `;
}

function renderNotificationRow(notification) {
  const actor = notification.actorHandle || shortIdentity(notification.actorDid);
  const label = notification.type === 'reply_to_post'
    ? t('notifications.replyToPost')
    : t('notifications.replyToThread');
  const href = `#/boards/${encodeURIComponent(notification.boardId)}/threads/${encodeURIComponent(notification.threadId)}`;
  return `
    <a class="notification-row${notification.isRead ? '' : ' is-unread'}" href="${escapeAttribute(href)}" data-action="open-notification" data-notification-id="${escapeAttribute(notification.id)}">
      <span class="notification-avatar" aria-hidden="true">${escapeHtml((actor || 'E').charAt(0).toUpperCase())}</span>
      <span class="notification-copy"><strong>${escapeHtml(actor)}</strong><span>${escapeHtml(label)}</span></span>
      ${renderThreadTime(notification.createdAt, 'notification-time')}
      ${notification.isRead ? '' : '<span class="notification-unread-dot" aria-hidden="true"></span>'}
    </a>
  `;
}

function renderHome(viewModel, uiState = {}) {
  const boards = viewModel.boards ?? [];
  const preferences = normalizeUiPreferences(uiState.preferences);

  return `
    ${renderError(viewModel.error)}
    <section class="cols social-home mobile-focus-home" aria-labelledby="feed-title">
      ${renderLeftRail(viewModel, 'feed')}
      <section class="feed focus-feed" aria-labelledby="feed-title">
        <!-- The handoff's feed column carries no page heading — it opens
             straight into the composer and the stream. The heading stays for
             assistive tech, and the read-only state is already shown by the
             session pill in the header. -->
        <h1 id="feed-title" class="visually-hidden">${escapeHtml(t('home.title'))}</h1>
        ${renderMobileFocusStage(viewModel, boards, preferences)}
      </section>
      ${renderRightRail(viewModel, boards)}
    </section>
  `;
}

function renderBoards(viewModel) {
  return `
    ${renderError(viewModel.error)}
    <section class="cols" aria-labelledby="boards-title">
      ${renderLeftRail(viewModel, 'boards')}
      <section class="feed boards-page" aria-labelledby="boards-title">
        <div class="feed-head">
          <div>
            <p class="section-label">${escapeHtml(t('boards.kicker'))}</p>
            <h1 id="boards-title">${escapeHtml(t('boards.title'))}</h1>
            <p>${escapeHtml(t('boards.subtitle'))}</p>
          </div>
          <a class="primary-action" href="#/">${escapeHtml(t('common.backToFeed'))}</a>
        </div>
        ${renderBoardDirectory(viewModel.boards ?? [], {
          title: t('boards.directoryTitle'),
          emptyText: t('boards.directoryEmpty'),
        })}
      </section>
      ${renderRightRail(viewModel, viewModel.boards ?? [])}
    </section>
  `;
}

function renderBoard(viewModel, uiState = {}) {
  const board = viewModel.board ?? {};
  if (board.missing) {
    return renderMissingBoard(viewModel, board);
  }

  const boardTitle = board.title || viewModel.page?.title || t('common.board');
  const threads = viewModel.threads ?? [];
  const gate = boardPostingGate(board, viewModel.session);
  const postAction = renderBoardPostAction(viewModel, gate);
  const threadContext = {
    session: viewModel.session,
    boardId: board.id ?? '',
    boardSlug: board.slug ?? board.id ?? '',
    boardTitle: board.title ?? board.slug ?? board.id ?? '',
    canReply: Boolean(viewModel.actions?.canReply),
  };

  return `
    ${renderNotice(uiState.notice)}
    ${renderError(viewModel.error)}
    <section class="cols" aria-labelledby="board-title">
      ${renderLeftRail(viewModel, 'boards')}
      <section class="feed board-detail" aria-labelledby="board-title">
        <section class="board-head" aria-labelledby="board-title">
          <div class="heading">
            <p class="section-label">${escapeHtml(t('board.kicker'))}</p>
            <h1 id="board-title">${escapeHtml(boardTitle)}${gate.gated ? ` ${renderGateBadge(gate)}` : ''}</h1>
            ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
            ${gate.gated ? `<p class="gate-requirement">${escapeHtml(gate.description)}</p>` : ''}
            <p>${escapeHtml(t('board.description'))}</p>
          </div>
          <div class="permission-state" aria-label="${escapeAttribute(t('common.permission'))}">
            <span class="lbl">${escapeHtml(t('common.permission'))}</span>
            <span class="val">${renderPermissionLabel(viewModel)}</span>
            <span class="lbl">${escapeHtml(t('common.trustTier'))}</span>
            <span class="val">${escapeHtml(trustTierLabel(viewModel.session?.trustTier ?? 'anonymous'))}</span>
          </div>
          ${postAction}
        </section>
        <section class="card thread-list" aria-labelledby="thread-list-title">
          <div class="head">
            <h3 id="thread-list-title">${escapeHtml(t('board.threadListTitle', { count: threads.length }))}</h3>
            <span class="label-mono">${escapeHtml(t('board.activity'))}</span>
          </div>
          ${renderThreadList(threads, threadContext)}
        </section>
        ${renderExternalSection(board, viewModel.externalContent)}
      </section>
      ${renderRightRail(viewModel, viewModel.boards ?? [])}
    </section>
  `;
}

function renderThreadDetail(viewModel, uiState = {}) {
  const board = viewModel.board ?? {};
  if (board.missing) {
    return renderMissingBoard(viewModel, board);
  }

  const thread = viewModel.thread;
  const boardId = board.id || viewModel.route?.params?.boardId || '';
  const boardHref = `#/boards/${encodeURIComponent(boardId)}`;

  if (!thread) {
    return `
      ${renderError(viewModel.error)}
      <section class="cols" aria-labelledby="missing-thread-title">
        ${renderLeftRail(viewModel, 'boards')}
        <section class="feed thread-detail" aria-labelledby="missing-thread-title">
          <a class="back-link" href="${escapeAttribute(boardHref)}">${escapeHtml(t('common.backToBoard'))}</a>
          <section class="card not-found-page">
            <p class="section-label">${escapeHtml(t('notFound.kicker'))}</p>
            <h2 id="missing-thread-title">${escapeHtml(t('notFound.title'))}</h2>
            <p>${escapeHtml(t('notFound.body', { path: viewModel.route?.params?.threadId ?? '' }))}</p>
          </section>
        </section>
        ${renderRightRail(viewModel, viewModel.boards ?? [])}
      </section>
    `;
  }

  const title = thread.title || thread.subject || t('common.threadFallback');
  const locked = Boolean(thread.locked);
  const posts = thread.posts ?? [];
  const context = {
    session: viewModel.session,
    boardId: board.id ?? boardId,
    canReply: Boolean(viewModel.actions?.canReply),
    authenticated: Boolean(viewModel.session?.authenticated),
    thread,
    threadId: thread.id ?? '',
  };
  const replyCount = threadReplyCount(thread, posts);

  return `
    ${renderNotice(uiState.notice)}
    ${renderError(viewModel.error)}
    <section class="cols" aria-labelledby="thread-title">
      ${renderLeftRail(viewModel, 'boards')}
      <section class="feed thread-detail" aria-labelledby="thread-title">
        <a class="back-link" href="${escapeAttribute(boardHref)}">${escapeHtml(t('common.backToBoard'))}</a>
        <article class="thread-detail-shell">
          <header class="thread-hd">
            <p class="thread-crumb">${escapeHtml(t('thread.kicker'))}</p>
            <h1 id="thread-title">${escapeHtml(title)}${locked ? ` ${renderLockedBadge()}` : ''}</h1>
            <div class="thread-hd-meta">
              ${renderThreadIdentity(thread)}
              <span>${escapeHtml(t('board.replyCount', { count: replyCount }))}</span>
              ${renderThreadTime(thread.updatedAt ?? thread.createdAt)}
            </div>
            ${locked ? renderLockedBanner(thread.lockReasonCode) : ''}
          </header>
          <section class="thread-conversation" aria-labelledby="thread-replies-title">
            ${renderThreadOriginalPost(thread, context)}
            ${renderThreadReplyComposer({ locked, context })}
            ${renderThreadReplies(posts, context)}
          </section>
        </article>
      </section>
      ${renderThreadContextRail(viewModel, board)}
    </section>
  `;
}

function threadAuthor(thread) {
  return thread?.authorDid || thread?.subjectDid || thread?.author || null;
}

function authorHandle(entity) {
  if (!entity || typeof entity !== 'object') return null;
  const handle = String(entity.authorHandle ?? entity.author_handle ?? entity.handle ?? '').trim();
  return handle || null;
}

function authorDisplayName(entity) {
  const handle = authorHandle(entity);
  if (handle) return handle;
  return shortIdentity(threadAuthor(entity));
}

function threadReplyCount(thread, posts = []) {
  const rawCount = thread?.replyCount ?? thread?.replies;
  const count = Number(rawCount);
  return Number.isFinite(count) ? count : posts.length;
}

function threadTitle(thread) {
  return thread?.title || thread?.subject || t('common.threadFallback');
}

function threadBody(thread) {
  return thread?.body || thread?.content || thread?.text || threadTitle(thread);
}

function threadInitial(primary, fallback = 'T') {
  const value = String(primary || fallback || '').trim();
  return (value.charAt(0) || 'T').toUpperCase();
}

function renderPkPill(label = t('focus.passkeyCompact')) {
  return `<span class="pk-pill">${escapeHtml(label)}</span>`;
}

function renderThreadIdentity(entity) {
  const author = threadAuthor(entity);
  const label = authorDisplayName(entity);
  const signed = Boolean(author);
  return `
    <span class="thread-identity">
      <span class="did-handle"${author && label !== shortIdentity(author) ? ` title="${escapeAttribute(author)}"` : ''}>${escapeHtml(label)}</span>
      ${signed ? renderPkPill() : ''}
    </span>
  `;
}

function renderThreadTime(value, className = 'thread-time') {
  const label = value ? formatExpiry(value) : t('common.recent');
  const parsed = value ? new Date(value) : null;
  const datetime =
    parsed && !Number.isNaN(parsed.getTime()) ? ` datetime="${escapeAttribute(parsed.toISOString())}"` : '';

  return `<time class="${escapeAttribute(className)}"${datetime}>${escapeHtml(label)}</time>`;
}

function renderThreadOriginalPost(thread, context = {}) {
  const author = threadAuthor(thread);
  const authorLabel = authorDisplayName(thread);
  const signed = Boolean(author);
  const body = threadBody(thread);
  const threadId = context.threadId ?? thread?.id ?? '';
  const report = context.authenticated
    ? renderReportControl({
        targetKind: 'thread',
        targetRef: threadId,
        boardId: context.boardId ?? '',
      })
    : '';
  const ownerActions = renderOwnerActions(thread, 'thread', context, thread.title ?? '');

  return `
    <article class="thread-op">
      <div class="thread-post-lane">
        <div class="thread-op-avatar">${escapeHtml(threadInitial(threadTitle(thread), author))}</div>
        <span class="thread-line" aria-hidden="true"></span>
      </div>
      <div class="thread-post-content">
        <div class="thread-post-top">
          <span class="thread-author"${author && authorLabel !== shortIdentity(author) ? ` title="${escapeAttribute(author)}"` : ''}>${escapeHtml(authorLabel)}</span>
          <span class="thread-source">${escapeHtml(t('thread.originalMarker'))}${signed ? ` · <span class="thread-source-strong">${escapeHtml(t('thread.signedPk'))}</span>` : ''}</span>
          ${renderThreadTime(thread.createdAt ?? thread.updatedAt, 'thread-post-time')}
          ${ownerActions}
        </div>
        <div class="thread-body-copy">${renderThreadParagraphs(body)}</div>
        ${renderThreadActionRow({
          hearts: thread.likeCount ?? thread.likes ?? 0,
          comments: threadReplyCount(thread, thread.posts ?? []),
          reposts: thread.repostCount ?? 0,
          report,
        })}
      </div>
    </article>
  `;
}

function renderThreadParagraphs(value) {
  const text = String(value ?? '').trim();
  if (!text) return `<p>${escapeHtml(t('common.threadFallback'))}</p>`;

  return text
    .split(/\n{2,}/)
    .map((paragraph) => `<p>${escapeHtml(paragraph).replaceAll('\n', '<br>')}</p>`)
    .join('');
}

function renderThreadActionRow({ hearts = 0, comments = 0, reposts = 0, report = '' } = {}) {
  return `
    <div class="thread-action-row" aria-label="${escapeAttribute(t('thread.actionsAria'))}">
      ${renderThreadIconButton('heart', hearts)}
      ${renderThreadIconButton('comment', comments)}
      ${renderThreadIconButton('repost', reposts)}
      ${renderThreadIconButton('share', '')}
      ${report}
    </div>
  `;
}

function renderThreadIconButton(kind, label) {
  const content = label === '' ? '' : `<span>${escapeHtml(label)}</span>`;
  return `<button class="thread-action" type="button" aria-label="${escapeAttribute(t(`thread.action.${kind}`))}">${renderThreadActionIcon(kind)}${content}</button>`;
}

function renderThreadReplyComposer({ locked, context = {} } = {}) {
  const sessionIdentity = context.session?.subjectDid || context.session?.did || null;
  const canReply = Boolean(context.canReply) && !locked;
  const label = canReply ? t('common.reply') : locked ? t('moderation.lockedNoReply') : t('thread.loginToReply');
  const field = canReply
    ? `<button class="thread-composer-field" type="button">${escapeHtml(t('thread.composerPlaceholder'))}</button>`
    : `<a class="thread-composer-field" href="#/login">${escapeHtml(t('thread.composerPlaceholder'))}</a>`;

  return `
    <div class="thread-reply-composer">
      <div class="thread-reply-avatar${sessionIdentity ? '' : ' is-anonymous'}">${escapeHtml(sessionIdentity ? threadInitial(shortIdentity(sessionIdentity), sessionIdentity) : '·')}</div>
      ${field}
      <button class="thread-composer-send" type="button" ${canReply ? '' : 'disabled'}>${escapeHtml(label)}</button>
    </div>
  `;
}

function renderThreadReplies(posts, context = {}) {
  return `
    <section class="thread-replies" aria-labelledby="thread-replies-title">
      <div class="thread-replies-head">
        <h3 id="thread-replies-title">${escapeHtml(t('thread.repliesTitle', { count: posts.length }))}</h3>
      </div>
      ${
        posts.length
          ? posts.map((post) => renderThreadReplyItem(post, context)).join('')
          : `<p class="empty-state">${escapeHtml(t('thread.noReplies'))}</p>`
      }
    </section>
  `;
}

function renderThreadReplyItem(post, context = {}) {
  const anonymous = Boolean(context.anonymousReplies) || !post.authorDid && !post.subjectDid && !post.author;
  const author = post.authorDid || post.subjectDid || post.author || null;
  const displayName = authorDisplayName(post);
  const avatar = anonymous ? '·' : threadInitial(displayName, author);
  const authorLabel = anonymous ? t('common.anonymous') : displayName;
  const title = author && !anonymous && authorLabel !== shortIdentity(author) ? ` title="${escapeAttribute(author)}"` : '';

  if (post.removed) {
    return `
      <article class="thread-reply-item is-removed">
        <div class="thread-reply-avatar${anonymous ? ' is-anonymous' : ''}">${escapeHtml(avatar)}</div>
        <div class="thread-reply-content">
          <div class="thread-reply-top">
            <span class="thread-reply-name"${title}>${escapeHtml(authorLabel)}</span>
            ${renderThreadTime(post.createdAt ?? post.updatedAt, 'thread-reply-time')}
          </div>
          ${renderRemovedTombstone(post.reasonCode)}
        </div>
      </article>
    `;
  }

  const report = context.authenticated
    ? renderReportControl({
        targetKind: 'post',
        targetRef: post.id ?? '',
        boardId: context.boardId ?? '',
      })
    : '';
  const ownerActions = renderOwnerActions(
    post,
    'post',
    context,
    post.body ?? post.content ?? '',
  );

  return `
    <article class="thread-reply-item">
      <div class="thread-reply-avatar${anonymous ? ' is-anonymous' : ''}">${escapeHtml(avatar)}</div>
      <div class="thread-reply-content">
        <div class="thread-reply-top">
          <span class="thread-reply-name${anonymous ? ' is-anonymous' : ''}"${title}>${escapeHtml(authorLabel)}</span>
          ${renderThreadTime(post.createdAt ?? post.updatedAt, 'thread-reply-time')}
          ${ownerActions}
        </div>
        <div class="thread-reply-body">${renderThreadParagraphs(post.body ?? post.content ?? '')}</div>
        <div class="thread-mini-actions">
          ${renderThreadMiniAction('heart', post.likeCount ?? post.likes ?? 0)}
          ${renderThreadMiniAction('comment', post.replyCount ?? 0)}
          ${report}
        </div>
      </div>
    </article>
  `;
}

function renderOwnerActions(entity, entityType, context, currentValue) {
  const sessionDid = context.session?.subjectDid ?? context.session?.did ?? '';
  const authorDid = entity.authorDid ?? entity.subjectDid ?? entity.author ?? '';
  if (!sessionDid || sessionDid !== authorDid || !entity.id || !entity.revision) return '';

  const common =
    ` data-entity-type="${escapeAttribute(entityType)}"` +
    ` data-entity-id="${escapeAttribute(entity.id)}"` +
    ` data-board-id="${escapeAttribute(context.boardId ?? '')}"` +
    ` data-revision="${escapeAttribute(entity.revision)}"`;
  return `
    <span class="content-owner-actions">
      <button type="button" data-action="edit-own-content"${common} data-current-value="${escapeAttribute(currentValue)}">${escapeHtml(t('content.edit'))}</button>
      <button type="button" data-action="delete-own-content"${common}>${escapeHtml(t('content.delete'))}</button>
    </span>
  `;
}

function renderThreadMiniAction(kind, count) {
  return `<button class="thread-mini-action" type="button" aria-label="${escapeAttribute(t(`thread.action.${kind}`))}">${renderThreadActionIcon(kind)}<span>${escapeHtml(count)}</span></button>`;
}

function renderThreadContextRail(viewModel, board = {}) {
  const boardId = board.id || '';
  const boardTitle = board.title || board.id || t('common.board');
  const href = boardId ? `#/boards/${encodeURIComponent(boardId)}` : '#/boards';
  const permission = renderPermissionLabel(viewModel);
  const trustTier = trustTierLabel(viewModel.session?.trustTier ?? TRUST_TIERS.anonymous);

  return `
    <aside class="right-rail thread-context-rail" aria-label="${escapeAttribute(t('common.feedContextAria'))}">
      <section class="side-panel thread-board-card">
        <p class="section-label">${escapeHtml(t('thread.boardContext'))}</p>
        <a class="thread-board-title" href="${escapeAttribute(href)}">#${escapeHtml(boardTitle)}</a>
        <p class="thread-board-meta">${escapeHtml(permission)} · ${escapeHtml(t('common.trustTier'))}: ${escapeHtml(trustTier)}</p>
      </section>
      <section class="side-note">
        ${escapeHtml(t('home.feedNote'))}
      </section>
    </aside>
  `;
}

// The relay enforces posting gates at intent acceptance; this client-side
// check makes both the legacy tier gate and Board Access Policy v1 credential
// requirements discoverable before the user tries to write. Credential
// presentation remains app-mediated: the browser never receives Wallet data.
function boardPostingGate(board, session) {
  const minPostTier = board?.postingPolicy?.minPostTier ?? null;
  const credential = board?.accessPolicy?.credentialRequirement ?? null;
  const credentialGated = Boolean(credential);
  const tierGated = minPostTier === TRUST_TIERS.verifiedHuman;
  const gated = tierGated || credentialGated;
  const trustTier = session?.trustTier ?? TRUST_TIERS.anonymous;

  return {
    gated,
    kind: credentialGated ? 'credential' : 'tier',
    requiredTier: minPostTier,
    credential,
    description: credentialGated
      ? t('board.credentialRequirement', {
          credential: credential.credentialType || t('board.credentialFallback'),
          claims: credentialClaimSummary(credential.claims),
        })
      : t('board.gateRequirement', { tier: trustTierLabel(minPostTier) }),
    blocked:
      Boolean(session?.authenticated) &&
      (credentialGated || (tierGated && !meetsMinPostTier(trustTier, minPostTier))),
  };
}

function credentialClaimSummary(claims = []) {
  const visible = claims
    .filter((claim) => claim?.path && claim?.op === 'equals')
    .map((claim) => `${claim.path} = ${String(claim.value)}`);
  return visible.length ? visible.join(', ') : t('board.credentialClaimsFallback');
}

function renderGateBadge(gate = {}) {
  const label =
    gate.kind === 'credential' ? t('board.credentialGateBadge') : t('board.gateBadge');
  return `<span class="gate-badge">${escapeHtml(label)}</span>`;
}

function renderBoardPostAction(viewModel, gate) {
  if (gate.blocked) {
    return `
      <div class="gate-blocked" role="note">
        <button class="primary-action" type="button" disabled>${escapeHtml(t('common.newThread'))}</button>
        <p>${escapeHtml(gate.kind === 'credential'
          ? t('board.credentialBlockedMessage')
          : t('board.gateBlockedMessage', { tier: trustTierLabel(viewModel.session?.trustTier ?? TRUST_TIERS.anonymous) }))}</p>
      </div>
    `;
  }

  const boardId = viewModel.board?.id || viewModel.board?.slug || '';
  const boardAttribute = boardId ? ` data-board-id="${escapeAttribute(boardId)}"` : '';

  return viewModel.actions?.canCreateThread
    ? `<button class="primary-action" type="button" data-action="new-thread"${boardAttribute}>${escapeHtml(t('common.newThread'))}</button>`
    : `<a class="primary-action" href="#/login">${escapeHtml(t('board.signInToPost'))}</a>`;
}

function renderMissingBoard(viewModel, board) {
  const boards = viewModel.boards ?? [];
  const boardTitle = board.title || board.id || t('common.board');

  return `
    <section class="cols" aria-labelledby="missing-board-title">
      ${renderLeftRail(viewModel, 'boards')}
      <section class="feed board-detail" aria-labelledby="missing-board-title">
        <section class="feed-head">
          <div>
            <p class="section-label">${escapeHtml(t('board.notAvailableKicker'))}</p>
            <h1 id="missing-board-title">${escapeHtml(boardTitle)}</h1>
            <p>${escapeHtml(t('board.notAvailableBody'))}</p>
          </div>
          <a class="primary-action" href="#/">${escapeHtml(t('common.backToFeed'))}</a>
        </section>
        ${renderBoardDirectory(boards, {
          title: t('boards.fromRelayTitle'),
          emptyText: t('boards.fromRelayEmpty'),
        })}
      </section>
      ${renderRightRail(viewModel, boards)}
    </section>
  `;
}

function renderLogin(viewModel, loginState = {}) {
  const status = loginState.status ?? viewModel.session?.status ?? 'idle';
  const challenge = loginState.challenge ?? null;
  const requestedScopes = loginState.requestedScopes ?? [];
  const statusCopy = loginStatusCopy(status);

  return `
    ${renderError(viewModel.error)}
    <section class="login-grid" aria-labelledby="login-title">
      <div class="qr-block">
        ${renderChallengePayloadPreview(challenge)}
        <span class="label-mono">${escapeHtml(challenge ? t('login.scanWithApp') : t('login.appLogin'))}</span>
        <span class="qr-hint">${escapeHtml(challenge ? t('login.qrHint') : t('login.createApprovalRequest'))}</span>
      </div>
      <div class="card login-page">
        <p class="section-label">${escapeHtml(t('login.kicker'))}</p>
        <h2 id="login-title">${escapeHtml(t('login.title'))}</h2>
        <p>${escapeHtml(statusCopy.message)}</p>
        ${
          challenge
            ? `<button class="primary-action" type="button" data-action="poll-login">${escapeHtml(t('login.checkApproval'))}</button>`
            : `<button class="primary-action" type="button" data-action="start-login">${escapeHtml(statusCopy.button)}</button>`
        }
        ${challenge ? renderLoginChallengeDetails(challenge) : `<p class="scope-empty">${escapeHtml(t('login.noChallenge'))}</p>`}
        <p class="section-label">${escapeHtml(t('login.requestedScopes'))}</p>
        ${renderScopeChips(requestedScopes)}
      </div>
    </section>
    <aside class="info-banner">
      <span class="icon"></span>
      <div>
        <strong>${escapeHtml(t('login.identityStaysTitle'))}</strong>
        <span>${escapeHtml(t('login.identityStaysBody'))}</span>
      </div>
    </aside>
  `;
}

function renderSessions(viewModel, uiState = {}) {
  const session = viewModel.session ?? {};
  const scopes = session.scopes ?? [];
  const preferences = normalizeUiPreferences(uiState.preferences);
  const identity = shortIdentity(session.subjectDid || session.subject) || t('sessions.titleFallback');
  const trustTier = trustTierLabel(session.trustTier);

  return `
    ${renderError(viewModel.error)}
    <section class="settings-home" aria-labelledby="settings-title">
      <div class="settings-topbar">
        <span></span>
        <p id="settings-title" class="settings-title">${escapeHtml(t('settings.title'))}</p>
        <a href="#/" class="settings-done">${escapeHtml(t('settings.done'))}</a>
      </div>

      <section class="settings-identity-hero" aria-label="${escapeAttribute(t('settings.localIdentity'))}">
        <span class="settings-avatar" aria-hidden="true">${renderUserGlyph()}</span>
        <div>
          <h2>${escapeHtml(t('settings.localIdentity'))}</h2>
          <p>${escapeHtml(t('settings.localDidLine', { identity, trustTier }))}</p>
        </div>
        <span class="settings-edit">${escapeHtml(t('settings.edit'))}</span>
      </section>

      ${renderSettingsGroup(t('settings.identityGroup'), [
        renderSettingsRow({ icon: renderWalletGlyph(), title: t('settings.wallet.title'), code: 'WALLET', detail: t('settings.wallet.detail'), value: t('settings.wallet.value') }),
        renderSettingsRow({ icon: renderSyncGlyph(), title: t('settings.sync.title'), code: 'SYNC', detail: t('settings.sync.detail'), value: t('settings.sync.value') }),
        renderSettingsRow({ icon: renderShieldGlyph(), title: t('settings.audit.title'), code: 'ADMIN', detail: t('settings.audit.detail'), value: t('settings.audit.value') }),
        renderSettingsRow({ icon: t('settings.language.icon'), title: t('settings.language.title'), code: 'LANGUAGE', detail: t('settings.language.detail'), value: t('settings.language.value') }),
      ])}
      ${renderLanguagePicker()}

      ${renderSettingsGroup(t('settings.dailyGroup'), [
        renderSettingsRow({ icon: renderBellGlyph(), title: t('settings.inbox.title'), code: 'INBOX', detail: t('settings.inbox.detail'), value: t('settings.inbox.value') }),
        renderSettingsRow({ icon: renderNoticeGlyph(), title: t('settings.notifications.title'), code: 'NOTIFICATIONS', detail: t('settings.notifications.detail'), value: t('settings.notifications.value') }),
        renderSettingsRow({ icon: 'A', title: t('settings.reading.title'), code: 'READING', detail: t('settings.reading.detail'), value: t('settings.reading.value') }),
      ])}

      <section class="settings-preferences" aria-label="${escapeAttribute(t('settings.interfaceAria'))}">
        <p class="settings-group-label">${escapeHtml(t('settings.interfaceGroup'))}</p>
        <div class="settings-preference-block">
          <div class="settings-copy">
            <p class="section-label">${escapeHtml(t('settings.theme.label'))}</p>
            <h3>${escapeHtml(t('settings.theme.title'))}</h3>
            <p>${escapeHtml(t('settings.theme.body'))}</p>
          </div>
          <div class="theme-settings-grid">
            ${renderSceneThemePicker('personal', t('focus.personalScene'), preferences.personalTheme)}
            ${renderSceneThemePicker('forum', t('focus.forumScene'), preferences.forumTheme)}
          </div>
        </div>
        <div class="settings-preference-block">
          <div class="settings-copy">
            <p class="section-label">${escapeHtml(t('settings.motion.label'))}</p>
            <h3>${escapeHtml(t('settings.motion.title'))}</h3>
            <p>${escapeHtml(t('settings.motion.body'))}</p>
          </div>
          <div class="motion-options">
            ${renderMotionOption('slide', t('settings.motion.slide.title'), t('settings.motion.slide.body'), preferences.motionMode)}
            ${renderMotionOption('book', t('settings.motion.book.title'), t('settings.motion.book.body'), preferences.motionMode)}
            ${renderMotionOption('cube', t('settings.motion.cube.title'), t('settings.motion.cube.body'), preferences.motionMode)}
          </div>
        </div>
      </section>

      ${renderSettingsGroup(t('settings.boundariesGroup'), [
        renderSettingsRow({ icon: renderKeyGlyph(), title: t('settings.recovery.title'), code: 'RECOVERY', detail: t('settings.recovery.detail'), value: t('settings.recovery.value'), tone: 'danger' }),
        renderSettingsRow({ icon: renderBlockedGlyph(), title: t('settings.blocked.title'), code: 'BLOCKED', detail: t('settings.blocked.detail'), value: t('settings.blocked.value') }),
      ])}

      <section class="settings-session-card" aria-label="${escapeAttribute(t('sessions.kicker'))}">
        <p class="section-label">${escapeHtml(t('common.scopes'))}</p>
        ${renderScopeChips(scopes)}
        ${
          viewModel.actions?.canRevokeSession
            ? `<button class="danger-action" type="button" data-action="revoke-session">${escapeHtml(t('sessions.revokeCurrent'))}</button>`
            : ''
        }
      </section>

      <p class="settings-version">${escapeHtml(t('settings.version'))}</p>
    </section>
  `;
}

function renderLanguagePicker() {
  const current = getCurrentLocale();
  return `
    <nav class="language-picker" aria-label="${escapeAttribute(t('settings.language.title'))}">
      ${SUPPORTED_LOCALES.map((locale) => `
        <a
          class="language-option${locale === current ? ' is-active' : ''}"
          href="?lang=${encodeURIComponent(locale)}#/sessions"
          lang="${escapeAttribute(locale)}"
          ${locale === current ? 'aria-current="true"' : ''}
        >${escapeHtml(LOCALE_NATIVE_NAMES[locale])}</a>
      `).join('')}
    </nav>
  `;
}

/// The feed stage. The handoff's revised web layout drops the tab row above
/// the feed, so this is a single chronological stream: compose, then posts
/// carrying their own source labels. Board conversations stay reachable from
/// the rail's boards destination.
function renderMobileFocusStage(viewModel, boards, preferences) {
  return `
    <section class="mobile-focus-stage" data-motion-mode="${escapeAttribute(preferences.motionMode)}" aria-label="${escapeAttribute(t('focus.mobileAria'))}">
      ${renderPersonalScene(viewModel, boards, preferences)}
    </section>
  `;
}

/// The stream itself: compose, then the posts. The scene label and meta row
/// went with the switcher — each post carries its own source label, which is
/// how the handoff explains why something is in the feed.
function renderPersonalScene(viewModel, boards, preferences) {
  return `
    <section class="scene-panel personal-scene" data-scene="personal" data-scene-theme="${escapeAttribute(preferences.personalTheme)}" aria-label="${escapeAttribute(t('focus.personal.title'))}">
      <div class="forum-list">
        ${renderComposeCard(viewModel)}
        ${renderRelayFeed(boards, viewModel)}
      </div>
    </section>
  `;
}

function renderSignedPill(label) {
  return `<span class="signed-pill">${escapeHtml(label)}</span>`;
}

function renderSettingsGroup(label, rows) {
  return `
    <section class="settings-group">
      <p class="settings-group-label">${escapeHtml(label)}</p>
      <div class="settings-list">${rows.join('')}</div>
    </section>
  `;
}

function renderSettingsRow({ icon, title, code, detail, value, tone = 'neutral' }) {
  return `
    <div class="settings-row">
      <span class="settings-row-icon" aria-hidden="true">${icon}</span>
      <span class="settings-row-copy">
        <span class="settings-row-title">${escapeHtml(title)} <em>${escapeHtml(code)}</em></span>
        <span class="settings-row-detail">${escapeHtml(detail)}</span>
      </span>
      <span class="settings-row-value is-${escapeAttribute(tone)}">${escapeHtml(value)}</span>
      <span class="settings-chevron" aria-hidden="true">⌄</span>
    </div>
  `;
}

function renderSceneThemePicker(scene, label, selectedTheme) {
  const options = [
    ['light', t('settings.theme.light')],
    ['dark', t('settings.theme.dark')],
    ['auto', t('settings.theme.auto')],
  ];

  return `
    <div class="scene-theme-picker" data-scene="${escapeAttribute(scene)}">
      <div class="scene-theme-head">
        <strong>${escapeHtml(label)}</strong>
        <span>${escapeHtml(scene === 'personal' ? t('settings.theme.personalTag') : t('settings.theme.forumTag'))}</span>
      </div>
      <div class="theme-option-row">
        ${options
          .map(([theme, text]) => {
            const selected = selectedTheme === theme;
            return `<button class="theme-option${selected ? ' is-selected' : ''}" type="button" data-action="set-scene-theme" data-scene="${escapeAttribute(scene)}" data-theme="${escapeAttribute(theme)}" aria-pressed="${selected ? 'true' : 'false'}"><span class="theme-swatch is-${escapeAttribute(theme)}"></span>${escapeHtml(text)}</button>`;
          })
          .join('')}
      </div>
    </div>
  `;
}

function renderMotionOption(mode, title, description, selectedMode) {
  const selected = selectedMode === mode;
  return `
    <button class="motion-option${selected ? ' is-selected' : ''}" type="button" data-action="set-motion-mode" data-motion="${escapeAttribute(mode)}" aria-pressed="${selected ? 'true' : 'false'}">
      <span class="radio-dot" aria-hidden="true"></span>
      <span><strong>${escapeHtml(title)}</strong><em>${escapeHtml(description)}</em></span>
    </button>
  `;
}

function renderNotFound(viewModel) {
  const path = viewModel?.route?.params?.path;

  return `
    ${renderError(viewModel?.error)}
    <section class="card not-found-page" aria-labelledby="not-found-title">
      <p class="section-label">${escapeHtml(t('notFound.kicker'))}</p>
      <h2 id="not-found-title">${escapeHtml(t('notFound.title'))}</h2>
      ${path ? `<p>${escapeHtml(t('notFound.body', { path }))}</p>` : ''}
      <nav class="route-links" aria-label="${escapeAttribute(t('common.routeRecovery'))}">
        <a href="#/">${escapeHtml(t('common.home'))}</a>
        <a href="#/boards">${escapeHtml(t('common.boards'))}</a>
      </nav>
    </section>
  `;
}

// Transient UI notices (report submitted, action recorded) share the
// info-banner shell used by semantic errors.
function renderNotice(notice) {
  if (!notice) return '';

  return `
    <aside class="info-banner is-${escapeAttribute(notice.tone ?? 'success')}" role="status">
      <span class="icon"></span>
      <div>
        <strong>${escapeHtml(notice.title ?? '')}</strong>
        <span>${escapeHtml(notice.message ?? '')}</span>
      </div>
    </aside>
  `;
}

function renderThreadDraftForm(draft) {
  if (!draft) return '';

  const boardId = draft.boardId ?? '';
  const review = draft.reviewing
    ? `
      <div class="thread-signing-review" role="note">
        <strong>${escapeHtml(t('compose.signingReview.title'))}</strong>
        <p>${escapeHtml(t('compose.signingReview.body'))}</p>
        <dl>
          <div><dt>${escapeHtml(t('compose.signingReview.action'))}</dt><dd>${escapeHtml(t('compose.signingReview.publishThread'))}</dd></div>
          <div><dt>${escapeHtml(t('common.board'))}</dt><dd>#${escapeHtml(boardId)}</dd></div>
          <div><dt>${escapeHtml(t('compose.threadDraft.titleLabel'))}</dt><dd>${escapeHtml(draft.title ?? '')}</dd></div>
          <div><dt>${escapeHtml(t('compose.signingReview.visibility'))}</dt><dd>${escapeHtml(t('compose.signingReview.publicFederated'))}</dd></div>
        </dl>
      </div>
    `
    : `
      <label class="thread-draft-label">
        <span>${escapeHtml(t('compose.threadDraft.titleLabel'))}</span>
        <input type="text" data-thread-draft-title value="${escapeAttribute(draft.title ?? '')}" placeholder="${escapeAttribute(t('compose.threadDraft.titlePlaceholder'))}" autocomplete="off" />
      </label>
    `;

  return `
    <section class="card thread-draft-form" data-thread-draft-form data-board-id="${escapeAttribute(boardId)}" aria-labelledby="thread-draft-title">
      <div class="head">
        <h3 id="thread-draft-title">${escapeHtml(t('compose.threadDraft.title'))}</h3>
        ${boardId ? `<span class="label-mono">#${escapeHtml(boardId)}</span>` : ''}
      </div>
      ${review}
      <div class="thread-draft-actions">
        <button class="secondary-action" type="button" data-action="cancel-thread-draft">${escapeHtml(t('common.cancel'))}</button>
        <button class="primary-action" type="button" data-action="${draft.reviewing ? 'confirm-thread-draft' : 'submit-thread-draft'}" data-board-id="${escapeAttribute(boardId)}">${escapeHtml(draft.reviewing ? t('compose.signingReview.confirm') : t('common.publish'))}</button>
      </div>
    </section>
  `;
}

function renderError(error) {
  const description = describeError(error);
  if (!description) return '';

  return `
    <aside class="info-banner is-${escapeAttribute(description.tone)}" role="status">
      <span class="icon"></span>
      <div>
        <strong>${escapeHtml(description.title)}</strong>
        <span>${escapeHtml(description.message)}</span>
      </div>
    </aside>
  `;
}

function renderComposeCard(viewModel) {
  const audience = viewModel.session?.authenticated ? t('home.signedBySession') : t('home.loginRequiredForPosting');
  const boardId = viewModel.board?.id || viewModel.board?.slug || viewModel.boards?.[0]?.id || viewModel.boards?.[0]?.slug || '';
  const boardAttribute = boardId ? ` data-board-id="${escapeAttribute(boardId)}"` : '';
  const action = viewModel.actions?.showLogin
    ? `<a class="primary-action" href="#/login">${escapeHtml(t('home.loginToPost'))}</a>`
    : `<button class="primary-action" type="button" data-action="new-thread"${boardAttribute}>${escapeHtml(t('common.publish'))}</button>`;

  // The design's compose row: avatar · italic prompt · publish pill, with the
  // post-type and audience affordances on a second line.
  return `
    <section class="compose" aria-label="${escapeAttribute(t('common.createPostAria'))}">
      <div class="compose-prompt">
        <span class="avatar av">${escapeHtml(sessionAvatarInitial(viewModel.session))}</span>
        <p class="hint">${escapeHtml(t('home.composePrompt'))}</p>
        ${action}
      </div>
      <div class="compose-actions">
        <button type="button">${escapeHtml(t('common.note'))}</button>
        <button type="button">${escapeHtml(t('common.murmur'))}</button>
        <a href="#/boards">${escapeHtml(t('home.composeBoardAction'))}</a>
        <span>${escapeHtml(audience)}</span>
      </div>
    </section>
  `;
}

function sessionAvatarInitial(session) {
  const identity = session?.subjectDid || session?.subject || '';
  const value = String(identity).replace(/^did:[a-z]+:/i, '');
  const first = [...value].find((char) => /\S/.test(char));
  return (first ?? 'E').toUpperCase();
}

/// Left rail — the design's `rail`: an icon nav followed by the subscribed
/// boards. Destinations with no route yet render as disabled rows (the
/// design's shape, without dead links). At tablet width CSS collapses this
/// to the icons-only strip.
function renderLeftRail(viewModel, active) {
  const authenticated = Boolean(viewModel.session?.authenticated);
  const navItems = [
    { id: 'feed', label: t('common.feed'), href: '#/', glyph: 'home' },
    { id: 'discover', label: t('home.discover'), glyph: 'search', upcoming: true },
    { id: 'notifications', label: t('home.notifications'), glyph: 'bell', upcoming: true },
    { id: 'boards', label: t('common.boards'), href: '#/boards', glyph: 'board' },
    {
      id: authenticated ? 'sessions' : 'login',
      label: authenticated ? t('common.you') : t('common.login'),
      href: authenticated ? '#/sessions' : '#/login',
      glyph: 'eye',
    },
  ];

  if (authenticated) {
    navItems.push({
      id: 'moderation',
      label: t('common.moderation'),
      href: '#/moderation',
      glyph: 'finger',
    });
  }

  const boards = viewModel.boards ?? [];

  return `
    <aside class="rail" aria-label="${escapeAttribute(t('common.navigationAria'))}">
      <nav class="rail-nav" aria-label="${escapeAttribute(t('common.navAria'))}">
        <p class="rail-label">${escapeHtml(t('common.navigate'))}</p>
        ${navItems.map((item) => renderRailNavItem(item, active)).join('')}
      </nav>
      <div class="rail-block rail-boards">
        <p class="rail-label">${escapeHtml(t('home.subscribedBoards'))} · ${escapeHtml(String(boards.length))}</p>
        ${
          boards.length
            ? boards.slice(0, 6).map((board) => renderRailBoardRow(board)).join('')
            : `<span class="rail-muted">${escapeHtml(t('common.noBoardsYet'))}</span>`
        }
      </div>
    </aside>
  `;
}

function renderRailNavItem(item, active) {
  const glyph = icon(item.glyph, 22, 'rail-icon');
  const label = `<span>${escapeHtml(item.label)}</span>`;

  if (item.upcoming) {
    return `<span class="rail-item is-upcoming" aria-disabled="true" title="${escapeAttribute(t('common.comingSoon'))}">${glyph}${label}</span>`;
  }

  const current = item.id === active ? ' aria-current="page"' : '';
  return `<a class="rail-item" href="${escapeAttribute(item.href)}"${current}>${glyph}${label}</a>`;
}

function renderRailBoardRow(board) {
  const title = board.title || board.slug || board.id || t('common.board');
  const href = `#/boards/${encodeURIComponent(board.id || board.slug || '')}`;
  const permission = board.permissions?.canWrite ? t('board.permissionWrite') : t('board.permissionRead');

  return `
    <a class="follow-row rail-board-row" href="${escapeAttribute(href)}">
      <span class="hashav" aria-hidden="true">#</span>
      <span class="meta">
        <span class="n">${escapeHtml(title)}</span>
        ${board.description ? `<span class="h">${escapeHtml(board.description)}</span>` : ''}
      </span>
      <span class="ago">${escapeHtml(permission)}</span>
    </a>
  `;
}

/// Right rail — the design's two context cards: the boards the relay is
/// serving, and the local-first promise block.
function renderRightRail(viewModel, boards) {
  return `
    <aside class="right-rail" aria-label="${escapeAttribute(t('common.feedContextAria'))}">
      <section class="side-panel card">
        <p class="section-label">${escapeHtml(t('home.subscribedBoards'))}</p>
        ${
          boards.length
            ? boards
                .slice(0, 4)
                .map((board) => {
                  const title = board.title || board.slug || board.id;
                  const href = `#/boards/${encodeURIComponent(board.id || board.slug || '')}`;
                  const permission = board.permissions?.canWrite ? t('board.permissionWrite') : t('board.permissionRead');
                  return `<a class="trend" href="${escapeAttribute(href)}"><span class="tag">#${escapeHtml(title)}</span><span class="n">${escapeHtml(permission)}</span></a>`;
                })
                .join('')
            : `<span>${escapeHtml(t('common.noBoardsYet'))}</span>`
        }
      </section>
      <section class="side-panel card promise-card">
        <p class="section-label">${escapeHtml(t('home.promiseTitle'))}</p>
        <div class="mini-promise">
          <span class="dot is-moss" aria-hidden="true"></span>
          <span class="tx"><b>${escapeHtml(t('home.promiseLocalTitle'))}</b>${escapeHtml(t('home.promiseLocalBody'))}</span>
        </div>
        <div class="mini-promise">
          <span class="dot is-accent" aria-hidden="true"></span>
          <span class="tx"><b>${escapeHtml(t('home.promiseConsentTitle'))}</b>${escapeHtml(t('home.promiseConsentBody'))}</span>
        </div>
      </section>
      <section class="side-note">
        ${escapeHtml(t('home.feedNote'))}
      </section>
    </aside>
  `;
}

function renderRelayFeed(boards, viewModel) {
  let unavailableNotice = '';
  if (viewModel.publicFeed) {
    const threads = viewModel.publicFeed.threads ?? [];
    if (threads.length) {
      return `
        <section class="card thread-list home-public-feed" aria-label="${escapeAttribute(t('common.feed'))}">
          ${renderThreadList(threads, { session: viewModel.session })}
        </section>
      `;
    }

    if (!viewModel.publicFeed.unavailable) {
      return `<p class="empty-state">${escapeHtml(t('board.noThreads'))}</p>`;
    }

    unavailableNotice = `
      <aside class="info-banner is-warning" role="status">
        <span class="icon"></span>
        <div><span>${escapeHtml(t('home.publicFeedUnavailable'))}</span></div>
      </aside>
    `;
  }

  if (!boards.length) {
    return `${unavailableNotice}
      <article class="post empty-state-card">
        <div class="lane"><span class="av" aria-hidden="true">#</span></div>
        <div class="body">
          <div class="src">${escapeHtml(t('home.subscribedBoards'))}</div>
          <div class="text"><p>${escapeHtml(t('home.emptyBoardsBody'))}</p></div>
        </div>
      </article>
    `;
  }

  return `${unavailableNotice}${boards.map((board) => renderBoardFeedPost(board, viewModel)).join('')}`;
}

/// Feed card — the design's `post` anatomy: an avatar lane beside a body of
/// source row → author row → heading → text → action row. The relay feed
/// carries boards, so the actions are the board's real affordances rendered
/// as the design's icon buttons (no invented engagement counts).
function renderBoardFeedPost(board, viewModel) {
  const title = board.title || board.slug || board.id || t('common.board');
  const boardId = board.id || board.slug || title;
  const hostName = viewModel.host?.displayName || t('common.relay');
  const description = board.description;
  const href = `#/boards/${encodeURIComponent(boardId)}`;
  const canWrite = Boolean(board.permissions?.canWrite);

  return `
    <article class="post post-board${canWrite ? ' signed' : ''}">
      <div class="lane">
        <span class="av" aria-hidden="true">#</span>
      </div>
      <div class="body">
        <div class="row1">
          <a class="handle" href="${escapeAttribute(href)}">${escapeHtml(title)}${canWrite ? sealIcon(13) : ''}</a>
          <span class="when">${escapeHtml(hostName)}</span>
        </div>
        <div class="src">${escapeHtml(t('home.boardSource', { slug: boardId }))}</div>
        ${description ? `<div class="text"><p>${escapeHtml(description)}</p></div>` : ''}
        <div class="actions">
          <a class="act" href="${escapeAttribute(href)}">${icon('board', 21)}<span class="c">${escapeHtml(t('home.openBoard'))}</span></a>
          <span class="act is-static">${icon(canWrite ? 'write' : 'read', 21)}<span class="c">${escapeHtml(canWrite ? t('home.postingAllowedByRelay') : t('home.readOnlyFromRelay'))}</span></span>
        </div>
      </div>
    </article>
  `;
}

function renderBoardDirectory(boards, { title, emptyText }) {
  if (!boards.length) {
    return `
      <section class="card directory board-directory" aria-labelledby="board-directory-title">
        <h3 id="board-directory-title">${escapeHtml(title)}</h3>
        <p>${escapeHtml(emptyText)}</p>
      </section>
    `;
  }

  return `
    <section class="card directory board-directory" aria-labelledby="board-directory-title">
      <div class="directory-head">
        <h3 id="board-directory-title">${escapeHtml(title)}</h3>
        <span class="label-mono">${escapeHtml(t('common.publicCount', { count: boards.length }))}</span>
      </div>
      <ul>
        ${boards.map(renderBoardDirectoryItem).join('')}
      </ul>
    </section>
  `;
}

function renderBoardDirectoryItem(board) {
  const title = board.title || board.id || t('common.board');
  const href = `#/boards/${encodeURIComponent(board.id || '')}`;
  const gate = boardPostingGate(board, null);

  return `
    <li>
      <a href="${escapeAttribute(href)}">${escapeHtml(title)}${gate.gated ? ` ${renderGateBadge(gate)}` : ''}</a>
      <span class="perm${board.permissions?.canWrite ? '' : ' read'}">${escapeHtml(board.permissions?.canWrite ? t('boards.posting') : t('boards.readOnly'))}</span>
      ${board.description ? `<p class="descr">${escapeHtml(board.description)}</p>` : ''}
    </li>
  `;
}

function renderThreadList(threads, context = {}) {
  if (!threads.length) {
    return `<p class="empty-state">${escapeHtml(t('board.noThreads'))}</p>`;
  }

  return `
    <ul>
      ${threads.map((thread) => renderThreadItem(thread, context)).join('')}
    </ul>
  `;
}

function renderThreadItem(thread, context = {}) {
  const title = threadTitle(thread);
  const author = threadAuthor(thread);
  const signed = Boolean(author);
  const initial = threadInitial(title, authorDisplayName(thread) || author);
  const locked = Boolean(thread.locked);
  const posts = thread.posts ?? [];
  const threadId = thread.id ?? '';
  const authenticated = Boolean(context.session?.authenticated);
  const boardId = thread.boardId || context.boardId || '';
  const boardSlug = thread.boardSlug || context.boardSlug || boardId;
  const boardTitle = thread.boardTitle || context.boardTitle || boardId;
  const href = threadId && boardSlug
    ? `#/boards/${encodeURIComponent(boardSlug)}/threads/${encodeURIComponent(threadId)}`
    : null;
  const replyCount = threadReplyCount(thread, posts);
  const status = locked ? t('error.threadLocked.title') : t('thread.statusActive');
  const report = authenticated
    ? renderReportControl({
        targetKind: 'thread',
        targetRef: threadId,
        boardId,
      })
    : '';
  const titleContent = `${escapeHtml(title)}${locked ? ` ${renderLockedBadge()}` : ''}`;
  const rowBody = `
    <span class="board-thread-avatar">${escapeHtml(initial)}</span>
    <span class="board-thread-copy">
      ${boardTitle ? `<span class="board-thread-board"><span aria-hidden="true">#</span>${escapeHtml(boardTitle)}</span>` : ''}
      <span class="board-thread-status"><span class="d${replyCount === 0 ? ' new' : ''}" aria-hidden="true"></span>${escapeHtml(t('board.replyCount', { count: replyCount }))} · ${escapeHtml(status)}</span>
      <span class="board-thread-title">${titleContent}</span>
      <span class="board-thread-by">
        ${renderThreadIdentity(thread)}
        ${renderThreadTime(thread.updatedAt ?? thread.createdAt, 'board-thread-time')}
      </span>
      ${locked ? renderLockedBanner(thread.lockReasonCode) : ''}
    </span>
  `;

  return `
    <li class="board-thread-row${signed ? ' is-signed' : ''}${locked ? ' is-locked' : ''}"${locked ? ' data-locked="true"' : ''}${threadId ? ` data-thread-id="${escapeAttribute(threadId)}"` : ''}>
      ${
        href
          ? `<a class="board-thread-link thread-title-link" href="${escapeAttribute(href)}">${rowBody}</a>`
          : `<div class="board-thread-link">${rowBody}</div>`
      }
      ${report ? `<div class="board-thread-tools">${report}</div>` : ''}
    </li>
  `;
}

// Tombstone for a post removed from this board projection: the content is
// stripped, only the reason code remains visible (to everyone, including the
// author — constitution-mandated visibility).
function renderRemovedTombstone(reasonCode) {
  return `
    <p class="post-tombstone" role="note">
      ${escapeHtml(t('moderation.removedTombstone', { reason: reasonCodeLabel(reasonCode) }))}
    </p>
  `;
}

// Curated federated ("站外 / fediverse") content. Constitution invariants:
// it renders ONLY on boards the host opted into (external_inclusion), is always
// labeled with its origin (instance + actor) and compliance level, is visually
// distinct from native posts, and is NEVER presented as verified. When the
// board did not opt in, nothing renders (and the data layer made no fetch).
function renderExternalSection(board, externalContent) {
  if (board?.postingPolicy?.externalInclusion !== true) {
    return '';
  }

  const items = externalContent?.items ?? [];
  const unavailable = Boolean(externalContent?.unavailable);

  const body = unavailable
    ? `<p class="empty-state">${escapeHtml(t('board.external.unavailable'))}</p>`
    : items.length
      ? `<ul class="external-list">${items.map(renderExternalItem).join('')}</ul>`
      : `<p class="empty-state">${escapeHtml(t('board.external.empty'))}</p>`;

  return `
    <section class="card external-section" aria-labelledby="external-section-title" data-external-section>
      <div class="head">
        <h3 id="external-section-title">${escapeHtml(t('board.external.title'))}</h3>
        <span class="external-origin-badge">${escapeHtml(t('board.external.badge'))}</span>
      </div>
      <p class="external-disclaimer" role="note">${escapeHtml(t('board.external.disclaimer'))}</p>
      ${body}
    </section>
  `;
}

function renderExternalItem(item) {
  const origin = item.instance || item.actorUri || t('board.external.unknownOrigin');
  const actor = item.actorUri || t('board.external.unknownActor');

  return `
    <li class="external-item" data-external-item>
      <div class="external-item-head">
        <span class="external-origin">${escapeHtml(
          t('board.external.from', { instance: origin }),
        )}</span>
        ${renderComplianceBadge(item.complianceLevel)}
      </div>
      <p class="external-body">${escapeHtml(item.content ?? '')}</p>
      <p class="external-actor">${escapeHtml(
        t('board.external.actor', { actor }),
      )}</p>
    </li>
  `;
}

// compatible = instance we assessed; unknown = un-assessed / lower-ranked.
function renderComplianceBadge(level) {
  const compatible = level === 'compatible';
  const label = compatible
    ? t('board.external.compliance.compatible')
    : t('board.external.compliance.unknown');

  return `<span class="compliance-badge is-${compatible ? 'compatible' : 'unknown'}">${escapeHtml(label)}</span>`;
}

function renderLockedBadge() {
  return `<span class="locked-badge">${escapeHtml(t('moderation.target.thread'))} · ${escapeHtml(t('error.threadLocked.title'))}</span>`;
}

function renderLockedBanner(lockReasonCode) {
  return `
    <p class="locked-banner" role="note">
      ${escapeHtml(t('moderation.lockedBanner', { reason: reasonCodeLabel(lockReasonCode) }))}
    </p>
  `;
}

// Inline report picker (signed-in sessions only). The reason enum mirrors the
// relay contract; "other" requires a note, enforced again relay-side.
function renderReportControl({ targetKind, targetRef, boardId }) {
  const targetData = `data-target-kind="${escapeAttribute(targetKind)}" data-target-ref="${escapeAttribute(targetRef)}" data-board-id="${escapeAttribute(boardId)}"`;

  return `
    <details class="report-control">
      <summary class="report-trigger">${escapeHtml(t('report.action'))}</summary>
      <form class="report-form" aria-label="${escapeAttribute(t('report.formAria'))}" data-report-form ${targetData}>
        <label class="report-field">
          <span>${escapeHtml(t('report.reasonLabel'))}</span>
          <select data-report-reason>
            ${REPORT_REASON_CODES.map(
              (code) =>
                `<option value="${escapeAttribute(code)}">${escapeHtml(reasonCodeLabel(code))}</option>`,
            ).join('')}
          </select>
        </label>
        <label class="report-field">
          <span>${escapeHtml(t('report.noteLabel'))}</span>
          <textarea data-report-note rows="2"></textarea>
        </label>
        <p class="report-note-hint">${escapeHtml(t('report.noteRequiredHint'))}</p>
        <button type="button" class="primary-action" data-action="submit-report" ${targetData}>${escapeHtml(t('report.submit'))}</button>
      </form>
    </details>
  `;
}

function renderModeration(viewModel, uiState = {}) {
  const moderation = viewModel.moderation ?? {
    status: 'signed_out',
    reportGroups: [],
    auditActions: [],
    error: null,
  };

  return `
    ${renderNotice(uiState.notice)}
    ${renderError(viewModel.error)}
    <section class="cols" aria-labelledby="moderation-title">
      ${renderLeftRail(viewModel, 'moderation')}
      <section class="feed moderation-console" aria-labelledby="moderation-title">
        <div class="feed-head">
          <div>
            <p class="section-label">${escapeHtml(t('moderation.kicker'))}</p>
            <h1 id="moderation-title">${escapeHtml(t('moderation.title'))}</h1>
            <p>${escapeHtml(t('moderation.subtitle'))}</p>
          </div>
          <a class="primary-action" href="#/">${escapeHtml(t('common.backToFeed'))}</a>
        </div>
        ${renderModerationBody(moderation)}
      </section>
      ${renderRightRail(viewModel, viewModel.boards ?? [])}
    </section>
  `;
}

function renderModerationBody(moderation) {
  if (moderation.status === 'signed_out') {
    return `
      <section class="card moderation-state" aria-labelledby="moderation-signed-out-title">
        <h3 id="moderation-signed-out-title">${escapeHtml(t('moderation.signedOut.title'))}</h3>
        <p>${escapeHtml(t('moderation.signedOut.body'))}</p>
        <a class="primary-action" href="#/login">${escapeHtml(t('common.login'))}</a>
      </section>
    `;
  }

  if (moderation.status === 'not_moderator') {
    return `
      <section class="card moderation-state moderation-forbidden" aria-labelledby="moderation-forbidden-title">
        <p class="section-label">${escapeHtml(t('moderation.notModerator.kicker'))}</p>
        <h3 id="moderation-forbidden-title">${escapeHtml(t('moderation.notModerator.title'))}</h3>
        <p>${escapeHtml(t('moderation.notModerator.body'))}</p>
      </section>
    `;
  }

  return `
    ${renderModerationQueue(moderation.reportGroups ?? [])}
    ${renderModerationAudit(moderation.auditActions ?? [])}
  `;
}

function renderModerationQueue(reportGroups) {
  const reportCount = reportGroups.reduce(
    (total, group) => total + group.reports.length,
    0,
  );

  if (!reportCount) {
    return `
      <section class="card moderation-queue" aria-labelledby="moderation-queue-title">
        <h3 id="moderation-queue-title">${escapeHtml(t('moderation.queueTitle', { count: 0 }))}</h3>
        <p class="empty-state">${escapeHtml(t('moderation.queueEmpty'))}</p>
      </section>
    `;
  }

  return `
    <section class="card moderation-queue" aria-labelledby="moderation-queue-title">
      <h3 id="moderation-queue-title">${escapeHtml(t('moderation.queueTitle', { count: reportCount }))}</h3>
      ${reportGroups.map(renderModerationBoardGroup).join('')}
    </section>
  `;
}

function renderModerationBoardGroup(group) {
  return `
    <section class="moderation-board-group" data-board-id="${escapeAttribute(group.boardId)}">
      <p class="label-mono">${escapeHtml(t('moderation.boardGroup', { board: group.boardId }))}</p>
      ${group.reports.map(renderModerationReport).join('')}
    </section>
  `;
}

function renderModerationReport(report) {
  return `
    <article class="moderation-report" data-report-id="${escapeAttribute(report.id ?? '')}">
      <div class="moderation-report-meta">
        <span class="target-kind">${escapeHtml(targetKindLabel(report.targetKind))}</span>
        <code>${escapeHtml(report.targetRef)}</code>
        <span class="reason-chip">${escapeHtml(reasonCodeLabel(report.reasonCode))}</span>
        <span class="ago">${escapeHtml(report.insertedAt ? formatExpiry(report.insertedAt) : t('common.recent'))}</span>
      </div>
      ${report.note ? `<p class="moderation-note">${escapeHtml(t('moderation.note'))} · ${escapeHtml(report.note)}</p>` : ''}
      <p class="moderation-reporter">${escapeHtml(t('moderation.reporter'))} · ${escapeHtml(shortIdentity(report.reporterDid))}</p>
      <div class="moderation-actions">
        ${actionsForTargetKind(report.targetKind)
          .map((action) => renderModerationActionButton(action, report))
          .join('')}
      </div>
    </article>
  `;
}

function renderModerationActionButton(action, report) {
  return `<button type="button" class="moderation-action-btn${action === 'dismiss_report' ? '' : ' is-primary'}" data-action="moderation-action" data-mod-action="${escapeAttribute(action)}" data-report-id="${escapeAttribute(report.id ?? '')}" data-target-ref="${escapeAttribute(report.targetRef)}" data-board-id="${escapeAttribute(report.boardId)}" data-reason-code="${escapeAttribute(report.reasonCode ?? '')}">${escapeHtml(moderationActionLabel(action))}</button>`;
}

function renderModerationAudit(auditActions) {
  if (!auditActions.length) {
    return `
      <section class="card moderation-audit" aria-labelledby="moderation-audit-title">
        <h3 id="moderation-audit-title">${escapeHtml(t('moderation.auditTitle'))}</h3>
        <p class="empty-state">${escapeHtml(t('moderation.auditEmpty'))}</p>
      </section>
    `;
  }

  return `
    <section class="card moderation-audit" aria-labelledby="moderation-audit-title">
      <h3 id="moderation-audit-title">${escapeHtml(t('moderation.auditTitle'))}</h3>
      <ul>
        ${auditActions.map(renderModerationAuditEntry).join('')}
      </ul>
    </section>
  `;
}

function renderModerationAuditEntry(action) {
  return `
    <li class="moderation-audit-entry">
      <strong>${escapeHtml(moderationActionLabel(action.action))}</strong>
      <code>${escapeHtml(action.targetRef)}</code>
      <span class="reason-chip">${escapeHtml(reasonCodeLabel(action.reasonCode))}</span>
      <span>#${escapeHtml(action.boardId)}</span>
      <span>${escapeHtml(shortIdentity(action.moderatorDid))}</span>
      <span class="ago">${escapeHtml(action.insertedAt ? formatExpiry(action.insertedAt) : t('common.recent'))}</span>
    </li>
  `;
}

function renderLoginChallengeDetails(challenge) {
  return `
    <dl class="challenge-details">
      <div>
        <dt>${escapeHtml(t('login.challengeId'))}</dt>
        <dd><code>${escapeHtml(challenge.challengeId)}</code></dd>
      </div>
      <div>
        <dt>${escapeHtml(t('login.expires'))}</dt>
        <dd>${escapeHtml(formatExpiry(challenge.expiresAt))}</dd>
      </div>
      <div>
        <dt>${escapeHtml(t('login.approval'))}</dt>
        <dd>${escapeHtml(t('login.approvalBody'))}</dd>
      </div>
    </dl>
  `;
}

function renderScopeChips(scopes) {
  if (!scopes.length) return `<p class="scope-empty">${escapeHtml(t('scope.empty'))}</p>`;

  return `
    <ul class="scope-list" aria-label="${escapeAttribute(t('common.scopes'))}">
      ${scopes.map((scope) => `<li>${escapeHtml(formatScope(scope))}</li>`).join('')}
    </ul>
  `;
}

function renderSessionMetric(label, value, copy) {
  return `
    <div>
      <dt>${escapeHtml(label)}</dt>
      <dd>${escapeHtml(value)}</dd>
      <p>${escapeHtml(copy)}</p>
    </div>
  `;
}

function renderChallengePayloadPreview(challenge) {
  if (!challenge) {
    return `
      <div class="challenge-payload-preview" aria-label="${escapeAttribute(t('login.emptyAria'))}">
        <strong>${escapeHtml(t('login.noActiveChallenge'))}</strong>
        <span>${escapeHtml(t('login.createApprovalRequest'))}</span>
      </div>
    `;
  }

  return `
    <div class="challenge-payload-preview" aria-label="${escapeAttribute(t('login.activeQrAria'))}">
      ${renderQrCodeSvg(challenge.qrPayload || challenge.deepLink || '', { ariaLabel: t('login.qrAria') })}
      <strong>${escapeHtml(challenge.challengeId)}</strong>
      <span>${escapeHtml(t('login.scanInstruction'))}</span>
    </div>
  `;
}

function renderPermissionLabel(viewModel) {
  if (viewModel.actions?.canCreateThread) return t('common.postingAvailable');
  if (viewModel.session?.authenticated) return t('common.readOnly');
  return t('common.readOnly');
}

function loginStatusCopy(status) {
  if (status === 'pending') {
    return {
      button: t('login.status.pending.button'),
      message: t('login.status.pending.message'),
      retry: false,
    };
  }

  if (status === 'rejected') {
    return {
      button: t('login.status.rejected.button'),
      message: t('login.status.rejected.message'),
      retry: true,
    };
  }

  if (status === 'expired') {
    return {
      button: t('login.status.expired.button'),
      message: t('login.status.expired.message'),
      retry: true,
    };
  }

  return {
    button: t('login.status.idle.button'),
    message: t('login.status.idle.message'),
    retry: false,
  };
}

function normalizeUiPreferences(preferences = {}) {
  return {
    activeScene: preferences.activeScene === 'forum' ? 'forum' : 'personal',
    personalTheme: normalizeTheme(preferences.personalTheme),
    forumTheme: normalizeTheme(preferences.forumTheme),
    motionMode: ['slide', 'book', 'cube'].includes(preferences.motionMode)
      ? preferences.motionMode
      : 'book',
    coachmarkDismissed: Boolean(preferences.coachmarkDismissed),
  };
}

function normalizeTheme(value) {
  return ['light', 'dark', 'auto'].includes(value) ? value : 'auto';
}

function renderThreadActionIcon(kind) {
  const paths = {
    heart: '<path d="M10 17 C6.2 14.2 4 11.9 4 8.8 C4 6.7 5.4 5.2 7.2 5.2 C8.4 5.2 9.3 5.8 10 6.8 C10.7 5.8 11.6 5.2 12.8 5.2 C14.6 5.2 16 6.7 16 8.8 C16 11.9 13.8 14.2 10 17 Z"/>',
    comment: '<path d="M5 5.5 H15 V12.5 H10.8 L7 15.5 V12.5 H5 Z"/>',
    repost: '<path d="M6 7 H14 L12 5 M14 13 H6 L8 15"/>',
    share: '<path d="M8.5 6.5 L10 5 L11.5 6.5 M10 5 V12"/><path d="M6 10 V15 H14 V10"/>',
  };

  return `<svg class="thread-action-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false">${paths[kind] ?? paths.heart}</svg>`;
}

function renderUserGlyph() {
  return `
    <svg viewBox="0 0 20 20" aria-hidden="true" focusable="false">
      <circle cx="10" cy="7" r="3.2" />
      <path d="M4 17 C5 13.2 7 11.6 10 11.6 C13 11.6 15 13.2 16 17" />
    </svg>
  `;
}

function renderWalletGlyph() {
  return `<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="5"/><circle cx="10" cy="10" r="2"/></svg>`;
}

function renderSyncGlyph() {
  return `<svg viewBox="0 0 20 20"><path d="M15 7 A5 5 0 0 0 6 5 L4 7 M5 13 A5 5 0 0 0 14 15 L16 13"/><path d="M4 4 V7 H7 M16 16 V13 H13"/></svg>`;
}

function renderShieldGlyph() {
  return `<svg viewBox="0 0 20 20"><path d="M10 3 L15 5 V9 C15 12.4 13.1 14.8 10 17 C6.9 14.8 5 12.4 5 9 V5 Z"/><path d="M8 10 L9.4 11.4 L12.4 8.2"/></svg>`;
}

function renderBellGlyph() {
  return `<svg viewBox="0 0 20 20"><path d="M6 9 C6 6.3 7.6 4.5 10 4.5 C12.4 4.5 14 6.3 14 9 V12 L15.5 14 H4.5 L6 12 Z"/><path d="M8.5 15 C9 16 11 16 11.5 15"/></svg>`;
}

function renderNoticeGlyph() {
  return `<svg viewBox="0 0 20 20"><path d="M10 3 L15 10 L10 17 L5 10 Z"/></svg>`;
}

function renderKeyGlyph() {
  return `<svg viewBox="0 0 20 20"><circle cx="7" cy="10" r="3"/><path d="M10 10 H17 M14 10 V13 M16 10 V12"/></svg>`;
}

function renderBlockedGlyph() {
  return `<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="7"/><path d="M5 5 L15 15"/></svg>`;
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll('`', '&#96;');
}

function safeHref(value) {
  const rawValue = String(value ?? '');
  try {
    const parsed = new URL(rawValue);
    if (['trisaura:', 'https:', 'http:'].includes(parsed.protocol)) {
      return escapeAttribute(rawValue);
    }
  } catch {
    return '#';
  }

  return '#';
}
