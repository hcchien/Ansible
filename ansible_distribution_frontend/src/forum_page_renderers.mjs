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
    <section class="home-overview" aria-labelledby="home-overview-title">
      <p class="section-label">Forum host overview</p>
      <h2 id="home-overview-title">${escapeHtml(hostName)}</h2>
      <p>Public reading is available from this web console.</p>
      <p class="permission-copy">${renderPermissionLabel(viewModel)}</p>
      <a class="route-link" href="#/boards">Browse boards</a>
    </section>
    ${renderBoardDirectory(boards, {
      title: 'Board directory',
      emptyText: 'No public boards are available.',
    })}
  `;
}

function renderBoards(viewModel) {
  return `
    ${renderError(viewModel.error)}
    <section class="boards-page" aria-labelledby="boards-title">
      <p class="section-label">Directory</p>
      <h2 id="boards-title">Boards</h2>
      <p>Browse public forum boards hosted by this relay.</p>
    </section>
    ${renderBoardDirectory(viewModel.boards ?? [], {
      title: 'Available boards',
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
    <section class="board-page" aria-labelledby="board-title">
      <div class="board-heading">
        <p class="section-label">Board</p>
        <h2 id="board-title">${escapeHtml(boardTitle)}</h2>
        ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
      </div>
      <div class="permission-state" aria-label="Permission state">
        <span>${renderPermissionLabel(viewModel)}</span>
        <strong>${escapeHtml(trustTierLabel(viewModel.session?.trustTier ?? 'anonymous'))}</strong>
      </div>
      ${postAction}
    </section>
    <section class="thread-list" aria-labelledby="thread-list-title">
      <h3 id="thread-list-title">Threads</h3>
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
    <section class="login-page" aria-labelledby="login-title">
      <p class="section-label">App-mediated session</p>
      <h2 id="login-title">App login challenge</h2>
      <p>${escapeHtml(statusCopy.message)}</p>
      <button class="primary-action" type="button" data-action="start-login">${escapeHtml(statusCopy.button)}</button>
      ${statusCopy.retry ? '<a class="route-link" href="#/login" data-action="start-login">Try again</a>' : ''}
    </section>
    ${challenge ? renderLoginChallenge(challenge, requestedScopes) : ''}
  `;
}

function renderSessions(viewModel) {
  const session = viewModel.session ?? {};
  const scopes = session.scopes ?? [];

  return `
    ${renderError(viewModel.error)}
    <section class="sessions-page" aria-labelledby="sessions-title">
      <p class="section-label">Current web session</p>
      <h2 id="sessions-title">${escapeHtml(shortIdentity(session.subjectDid || session.subject))}</h2>
      <dl class="session-details">
        <div>
          <dt>Trust tier</dt>
          <dd>${escapeHtml(trustTierLabel(session.trustTier))}</dd>
        </div>
        <div>
          <dt>Expiry</dt>
          <dd>${escapeHtml(formatExpiry(session.expiresAt))}</dd>
        </div>
      </dl>
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
    <section class="not-found-page" aria-labelledby="not-found-title">
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
    <aside class="error-banner is-${escapeAttribute(description.tone)}" role="status">
      <strong>${escapeHtml(description.title)}</strong>
      <span>${escapeHtml(description.message)}</span>
    </aside>
  `;
}

function renderBoardDirectory(boards, { title, emptyText }) {
  if (!boards.length) {
    return `
      <section class="board-directory" aria-labelledby="board-directory-title">
        <h3 id="board-directory-title">${escapeHtml(title)}</h3>
        <p>${escapeHtml(emptyText)}</p>
      </section>
    `;
  }

  return `
    <section class="board-directory" aria-labelledby="board-directory-title">
      <h3 id="board-directory-title">${escapeHtml(title)}</h3>
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
      ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
      <span>${board.permissions?.canWrite ? 'Posting available' : 'Read only'}</span>
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

  return `
    <li>
      <h4>${escapeHtml(title)}</h4>
      <p>${escapeHtml(shortIdentity(author))}</p>
    </li>
  `;
}

function renderLoginChallenge(challenge, requestedScopes) {
  return `
    <section class="login-challenge" aria-labelledby="challenge-title">
      <h3 id="challenge-title">Challenge details</h3>
      <dl>
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
      ${renderScopeChips(requestedScopes)}
    </section>
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
