import { PAGE_IDS } from './state_model.mjs';
import {
  describeError,
  formatExpiry,
  formatScope,
  shortIdentity,
  trustTierLabel,
} from './forum_ui_text.mjs';
import { escapeHtml } from './forum_shell_renderer.mjs';

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
  const hostName = viewModel.host?.displayName || 'Forum Relay';
  const boards = viewModel.boards ?? [];

  return `
    ${renderError(viewModel.error)}
    <section class="card home-overview" aria-labelledby="home-overview-title">
      <p class="section-label">OVERVIEW · 概覽</p>
      <h2 id="home-overview-title">${escapeHtml(hostName)}</h2>
      <p>This relay is a public reading surface. Posting remains tied to an app-approved or passkey-backed session, so the browser is only the window.</p>
      <p class="permission-copy">${renderPermissionLabel(viewModel)}</p>
      <a class="route-link" href="#/boards">Browse boards</a>
    </section>
    ${renderBoardDirectory(boards, {
      title: 'Board directory · 討論板目錄',
      emptyText: 'No public boards are available.',
    })}
  `;
}

function renderBoards(viewModel) {
  return `
    ${renderError(viewModel.error)}
    <section class="card boards-page" aria-labelledby="boards-title">
      <p class="section-label">DIRECTORY · 目錄</p>
      <h2 id="boards-title">Boards</h2>
      <p>Each board carries its own write policy. Open a board to inspect trust requirements before starting a signed thread.</p>
    </section>
    ${renderBoardDirectory(viewModel.boards ?? [], {
      title: 'Available boards · 可用討論板',
      emptyText: 'No boards are available.',
    })}
  `;
}

function renderBoard(viewModel) {
  const board = viewModel.board ?? {};
  const boardTitle = board.title || viewModel.page?.title || 'Board';
  const threads = viewModel.threads ?? [];
  const postAction = viewModel.actions?.canCreateThread
    ? '<button class="primary-action" type="button" data-action="new-thread">New thread</button>'
    : '<a class="primary-action" href="#/login">Sign in to post</a>';

  return `
    ${renderError(viewModel.error)}
    <section class="board-head" aria-labelledby="board-title">
      <div class="heading">
        <p class="section-label">BOARD · 討論板</p>
        <h2 id="board-title">${escapeHtml(boardTitle)}</h2>
        ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
      </div>
      <div class="permission-state" aria-label="Permission state">
        <span class="lbl">Permission</span>
        <span class="val">${renderPermissionLabel(viewModel)}</span>
        <span class="lbl">Trust tier</span>
        <span class="val">${escapeHtml(trustTierLabel(viewModel.session?.trustTier ?? 'anonymous'))}</span>
      </div>
      ${postAction}
    </section>
    <section class="card thread-list" aria-labelledby="thread-list-title">
      <div class="head">
        <h3 id="thread-list-title">Threads · ${threads.length}</h3>
        <span class="label-mono">RECENT ACTIVITY</span>
      </div>
      ${renderThreadList(threads)}
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
        ${renderQrPreview(challenge?.qrPayload ?? status)}
        <span class="label-mono">SCAN WITH ELIX APP</span>
        ${
          challenge
            ? `<a class="route-link" href="${safeHref(challenge.deepLink)}">Open in app</a>`
            : '<button class="primary-action" type="button" data-action="start-login">Create challenge</button>'
        }
      </div>
      <div class="card login-page">
        <p class="section-label">CHALLENGE · 挑戰</p>
        <h2 id="login-title">App login challenge</h2>
        <p>${escapeHtml(statusCopy.message)}</p>
        <button class="primary-action" type="button" data-action="start-login">${escapeHtml(statusCopy.button)}</button>
        ${challenge ? '<button class="header-action" type="button" data-action="poll-login">Check approval</button>' : ''}
        ${statusCopy.retry ? '<a class="route-link" href="#/login" data-action="start-login">Try again</a>' : ''}
        ${challenge ? renderLoginChallengeDetails(challenge) : ''}
        <p class="section-label">REQUESTED SCOPES · 要求權限</p>
        ${renderScopeChips(requestedScopes)}
      </div>
    </section>
    <aside class="info-banner">
      <span class="icon"></span>
      <div>
        <strong>The key stays in the app</strong>
        <span>Approving the challenge grants this browser only the scopes shown above. Posting still requires signed intent.</span>
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
      <p class="section-label">CURRENT SESSION · 當前工作階段</p>
      <h2 id="sessions-title">${escapeHtml(shortIdentity(session.subjectDid || session.subject))}</h2>
      <p>This browser session is scoped and revocable. It does not expose the app key material.</p>
      <dl class="session-details">
        ${renderSessionMetric('Trust tier', trustTierLabel(session.trustTier), 'Permission inherited from the approving app session.')}
        ${renderSessionMetric('Expiry', formatExpiry(session.expiresAt), 'The browser must ask the app again after this time.')}
      </dl>
      <p class="section-label">SCOPES · 授權範圍</p>
      ${renderScopeChips(scopes)}
      ${
        viewModel.actions?.canRevokeSession
          ? '<button class="danger-action" type="button" data-action="revoke-session">Revoke current session</button>'
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
      <p class="section-label">Not found</p>
      <h2 id="not-found-title">Route unavailable</h2>
      ${path ? `<p>${escapeHtml(path)} is not available in this forum console.</p>` : ''}
      <nav class="route-links" aria-label="Route recovery">
        <a href="#/">Home</a>
        <a href="#/boards">Boards</a>
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
        <span class="label-mono">${boards.length} PUBLIC</span>
      </div>
      <ul>
        ${boards.map(renderBoardDirectoryItem).join('')}
      </ul>
    </section>
  `;
}

function renderBoardDirectoryItem(board) {
  const title = board.title || board.id || 'Board';
  const href = `#/boards/${encodeURIComponent(board.slug || board.id || '')}`;

  return `
    <li>
      <a href="${escapeAttribute(href)}">${escapeHtml(title)}</a>
      <span class="perm${board.permissions?.canWrite ? '' : ' read'}">${board.permissions?.canWrite ? 'Posting' : 'Read only'}</span>
      ${board.description ? `<p class="descr">${escapeHtml(board.description)}</p>` : ''}
    </li>
  `;
}

function renderThreadList(threads) {
  if (!threads.length) {
    return '<p class="empty-state">No threads have been posted yet.</p>';
  }

  return `
    <ul>
      ${threads.map(renderThreadItem).join('')}
    </ul>
  `;
}

function renderThreadItem(thread) {
  const title = thread.title || thread.subject || 'Untitled thread';
  const author = thread.authorDid || thread.subjectDid || thread.author || null;
  const signed = Boolean(author);
  const initial = title.trim().charAt(0).toUpperCase() || 'T';

  return `
    <li${signed ? ' class="signed"' : ''}>
      <div class="av">${escapeHtml(initial)}</div>
      <div>
        <h4 class="ttl">${escapeHtml(title)}</h4>
        <p class="author">${escapeHtml(shortIdentity(author))}${signed ? '<span class="signed-dot"></span>signed' : ''}</p>
      </div>
      <div class="meta">
        <span class="replies">${escapeHtml(thread.replyCount ?? thread.replies ?? 0)} replies</span>
        <span class="ago">${escapeHtml(thread.updatedAt ? formatExpiry(thread.updatedAt) : 'recent')}</span>
      </div>
    </li>
  `;
}

function renderLoginChallengeDetails(challenge) {
  return `
    <dl class="challenge-details">
      <div>
        <dt>Challenge ID</dt>
        <dd><code>${escapeHtml(challenge.challengeId)}</code></dd>
      </div>
      <div>
        <dt>Expires</dt>
        <dd>${escapeHtml(formatExpiry(challenge.expiresAt))}</dd>
      </div>
      <div>
        <dt>Deep link</dt>
        <dd><a href="${safeHref(challenge.deepLink)}">${escapeHtml(challenge.deepLink)}</a></dd>
      </div>
      <div>
        <dt>QR payload</dt>
        <dd><code>${escapeHtml(challenge.qrPayload)}</code></dd>
      </div>
    </dl>
  `;
}

function renderScopeChips(scopes) {
  if (!scopes.length) return '<p class="scope-empty">No scopes granted.</p>';

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

function renderQrPreview(seed) {
  const cells = Array.from({ length: 144 }, (_, index) => {
    const code = String(seed ?? '').charCodeAt(index % String(seed ?? '').length || 0) || 17;
    const active = (index + code + index * 7) % 5 !== 0;
    const amber = active && (index + code) % 17 === 0;
    return `<i class="${active ? (amber ? 'amber' : '') : 'off'}"></i>`;
  });

  return `<div class="qr-preview" aria-label="Login challenge QR preview">${cells.join('')}</div>`;
}

function renderPermissionLabel(viewModel) {
  if (viewModel.actions?.canCreateThread) return 'Posting available';
  if (viewModel.session?.authenticated) return 'Read only';
  return 'Read only';
}

function loginStatusCopy(status) {
  if (status === 'pending') {
    return {
      button: 'Start app login',
      message: 'Approve this pending challenge in the app to continue.',
      retry: false,
    };
  }

  if (status === 'rejected') {
    return {
      button: 'Start app login',
      message: 'The app rejected this login challenge.',
      retry: true,
    };
  }

  if (status === 'expired') {
    return {
      button: 'Start app login',
      message: 'This login challenge expired.',
      retry: true,
    };
  }

  return {
    button: 'Start app login',
    message: 'Start a challenge and approve it in the app.',
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
