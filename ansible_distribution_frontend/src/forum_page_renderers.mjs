import { PAGE_IDS } from './state_model.mjs';
import {
  describeError,
  formatExpiry,
  formatScope,
  shortIdentity,
  trustTierLabel,
} from './forum_ui_text.mjs';
import { escapeHtml } from './forum_shell_renderer.mjs';
import { renderQrCodeSvg } from './qr_code.mjs';
import { t } from './web_i18n.mjs';

export function renderPageBody(viewModel, uiState = {}) {
  const pageId = viewModel?.page?.id ?? viewModel?.route?.pageId;

  switch (pageId) {
    case PAGE_IDS.home:
      return renderHome(viewModel);
    case PAGE_IDS.boards:
      return renderBoards(viewModel);
    case PAGE_IDS.board:
      return renderBoard(viewModel);
    case PAGE_IDS.login:
      return renderLogin(viewModel, uiState.login ?? {});
    case PAGE_IDS.sessions:
      return renderSessions(viewModel);
    default:
      return renderNotFound(viewModel);
  }
}

function renderHome(viewModel) {
  const boards = viewModel.boards ?? [];

  return `
    ${renderError(viewModel.error)}
    <section class="cols social-home" aria-labelledby="feed-title">
      ${renderLeftRail(viewModel, 'feed')}
      <section class="feed" aria-labelledby="feed-title">
        <div class="feed-head">
          <div>
            <p class="section-label">${escapeHtml(t('home.kicker'))}</p>
            <h1 id="feed-title">${escapeHtml(t('home.title'))}</h1>
            <p>${escapeHtml(t('home.subtitle'))}</p>
          </div>
          <span class="permission-copy">${renderPermissionLabel(viewModel)}</span>
        </div>
        ${renderComposeCard(viewModel)}
        <nav class="feed-tabs" aria-label="${escapeAttribute(t('common.feedFiltersAria'))}">
          <a aria-current="page" href="#/">${escapeHtml(t('common.feed'))}</a>
          <a href="#/">${escapeHtml(t('home.followingTab'))}</a>
          <a href="#/boards">${escapeHtml(t('home.boardsTab'))}</a>
          <a href="#/">${escapeHtml(t('home.circleTab'))}</a>
        </nav>
        ${renderRelayFeed(boards, viewModel)}
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

function renderBoard(viewModel) {
  const board = viewModel.board ?? {};
  if (board.missing) {
    return renderMissingBoard(viewModel, board);
  }

  const boardTitle = board.title || viewModel.page?.title || t('common.board');
  const threads = viewModel.threads ?? [];
  const postAction = viewModel.actions?.canCreateThread
    ? `<button class="primary-action" type="button" data-action="new-thread">${escapeHtml(t('common.newThread'))}</button>`
    : `<a class="primary-action" href="#/login">${escapeHtml(t('board.signInToPost'))}</a>`;

  return `
    ${renderError(viewModel.error)}
    <section class="cols" aria-labelledby="board-title">
      ${renderLeftRail(viewModel, 'boards')}
      <section class="feed board-detail" aria-labelledby="board-title">
        <section class="board-head" aria-labelledby="board-title">
          <div class="heading">
            <p class="section-label">${escapeHtml(t('board.kicker'))}</p>
            <h1 id="board-title">${escapeHtml(boardTitle)}</h1>
            ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
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
          ${renderThreadList(threads)}
        </section>
      </section>
      ${renderRightRail(viewModel, viewModel.boards ?? [])}
    </section>
  `;
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

function renderSessions(viewModel) {
  const session = viewModel.session ?? {};
  const scopes = session.scopes ?? [];

  return `
    ${renderError(viewModel.error)}
    <section class="card sessions-page" aria-labelledby="sessions-title">
      <p class="section-label">${escapeHtml(t('sessions.kicker'))}</p>
      <h2 id="sessions-title">${escapeHtml(shortIdentity(session.subjectDid || session.subject) || t('sessions.titleFallback'))}</h2>
      <p>${escapeHtml(t('sessions.description'))}</p>
      <dl class="session-details">
        ${renderSessionMetric(t('common.trustTier'), trustTierLabel(session.trustTier), t('sessions.trustTierHelp'))}
        ${renderSessionMetric(t('common.expiry'), formatExpiry(session.expiresAt), t('sessions.expiryHelp'))}
      </dl>
      <p class="section-label">${escapeHtml(t('common.scopes'))}</p>
      ${renderScopeChips(scopes)}
      ${
        viewModel.actions?.canRevokeSession
          ? `<button class="danger-action" type="button" data-action="revoke-session">${escapeHtml(t('sessions.revokeCurrent'))}</button>`
          : ''
      }
    </section>
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
  const action = viewModel.actions?.showLogin
    ? `<a class="primary-action" href="#/login">${escapeHtml(t('home.loginToPost'))}</a>`
    : `<button class="primary-action" type="button" data-action="new-thread">${escapeHtml(t('common.publish'))}</button>`;

  return `
    <section class="compose" aria-label="${escapeAttribute(t('common.createPostAria'))}">
      <div class="compose-prompt">
        <span class="avatar">E</span>
        <p>${escapeHtml(t('home.composePrompt'))}</p>
      </div>
      <div class="compose-actions">
        <button type="button">${escapeHtml(t('common.note'))}</button>
        <button type="button">${escapeHtml(t('common.murmur'))}</button>
        <a href="#/boards">${escapeHtml(t('home.composeBoardAction'))}</a>
        <span>${escapeHtml(audience)}</span>
        ${action}
      </div>
    </section>
  `;
}

function renderLeftRail(viewModel, active) {
  const navItems = [
    { id: 'feed', label: t('common.feed'), href: '#/' },
    { id: 'boards', label: t('common.boards'), href: '#/boards' },
  ];
  const upcomingItems = [t('home.discover'), t('home.notifications'), t('home.circleTab')];

  return `
    <aside class="rail" aria-label="${escapeAttribute(t('common.navigationAria'))}">
      <p class="rail-label">${escapeHtml(t('common.navigate'))}</p>
      <nav class="rail-nav">
        ${navItems
          .map((item) => {
            const current = item.id === active ? ' aria-current="page"' : '';
            return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
          })
          .join('')}
      </nav>
      <div class="rail-block">
        <p class="rail-label">${escapeHtml(t('common.comingSoon'))}</p>
        ${upcomingItems.map((label) => `<span class="rail-muted">${escapeHtml(label)}</span>`).join('')}
      </div>
      <div class="rail-block">
        <p class="rail-label">${escapeHtml(t('common.boards'))}</p>
        <span>${escapeHtml(t('common.boardCount', { count: (viewModel.boards ?? []).length }))}</span>
      </div>
    </aside>
  `;
}

function renderRightRail(viewModel, boards) {
  return `
    <aside class="right-rail" aria-label="${escapeAttribute(t('common.feedContextAria'))}">
      <section class="side-panel">
        <p class="section-label">${escapeHtml(t('home.subscribedBoards'))}</p>
        ${boards.length ? boards.slice(0, 4).map((board) => `<a href="#/boards/${encodeURIComponent(board.slug || board.id || '')}">#${escapeHtml(board.title || board.id)}</a>`).join('') : `<span>${escapeHtml(t('common.noBoardsYet'))}</span>`}
      </section>
      <section class="side-note">
        ${escapeHtml(t('home.feedNote'))}
      </section>
    </aside>
  `;
}

function renderRelayFeed(boards, viewModel) {
  if (!boards.length) {
    return `
      <article class="post empty-state-card">
        <div class="post-source">${escapeHtml(t('home.subscribedBoards'))}</div>
        <p class="post-body">${escapeHtml(t('home.emptyBoardsBody'))}</p>
      </article>
    `;
  }

  return boards.map((board) => renderBoardFeedPost(board, viewModel)).join('');
}

function renderBoardFeedPost(board, viewModel) {
  const title = board.title || board.id || t('common.board');
  const slug = board.slug || board.id || title;
  const hostName = viewModel.host?.displayName || t('common.relay');
  const description = board.description || t('home.boardFallbackDescription');
  const href = `#/boards/${encodeURIComponent(slug)}`;

  return `
    <article class="post post-board">
      <div class="post-source">${escapeHtml(t('home.boardSource', { slug }))}</div>
      <div class="post-author">
        <span class="avatar">${escapeHtml(title.charAt(0).toUpperCase() || 'B')}</span>
        <div>
          <strong>${escapeHtml(title)}</strong>
          <span>${escapeHtml(hostName)}</span>
        </div>
      </div>
      <p class="post-body">${escapeHtml(description)}</p>
      <div class="post-actions">
        <a href="${escapeAttribute(href)}">${escapeHtml(t('home.openBoard'))}</a>
        <span>${escapeHtml(board.permissions?.canWrite ? t('home.postingAllowedByRelay') : t('home.readOnlyFromRelay'))}</span>
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
  const href = `#/boards/${encodeURIComponent(board.slug || board.id || '')}`;

  return `
    <li>
      <a href="${escapeAttribute(href)}">${escapeHtml(title)}</a>
      <span class="perm${board.permissions?.canWrite ? '' : ' read'}">${escapeHtml(board.permissions?.canWrite ? t('boards.posting') : t('boards.readOnly'))}</span>
      ${board.description ? `<p class="descr">${escapeHtml(board.description)}</p>` : ''}
    </li>
  `;
}

function renderThreadList(threads) {
  if (!threads.length) {
    return `<p class="empty-state">${escapeHtml(t('board.noThreads'))}</p>`;
  }

  return `
    <ul>
      ${threads.map(renderThreadItem).join('')}
    </ul>
  `;
}

function renderThreadItem(thread) {
  const title = thread.title || thread.subject || t('common.threadFallback');
  const author = thread.authorDid || thread.subjectDid || thread.author || null;
  const signed = Boolean(author);
  const initial = title.trim().charAt(0).toUpperCase() || 'T';

  return `
    <li${signed ? ' class="signed"' : ''}>
      <div class="av">${escapeHtml(initial)}</div>
      <div>
        <h4 class="ttl">${escapeHtml(title)}</h4>
        <p class="author">${escapeHtml(shortIdentity(author))}${signed ? `<span class="signed-dot"></span>${escapeHtml(t('common.signed'))}` : ''}</p>
      </div>
      <div class="meta">
        <span class="replies">${escapeHtml(t('board.replyCount', { count: thread.replyCount ?? thread.replies ?? 0 }))}</span>
        <span class="ago">${escapeHtml(thread.updatedAt ? formatExpiry(thread.updatedAt) : t('common.recent'))}</span>
      </div>
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
    <ul class="scope-list" aria-label="Scopes">
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
