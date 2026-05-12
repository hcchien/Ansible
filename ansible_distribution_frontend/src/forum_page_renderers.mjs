import { PAGE_IDS } from './state_model.mjs';
import {
  describeError,
  formatExpiry,
  formatScope,
  shortIdentity,
  trustTierLabel,
} from './forum_ui_text.mjs';
import { escapeHtml } from './forum_shell_renderer.mjs';

const FEED_POSTS = [
  {
    source: 'FROM A FOLLOW',
    type: 'MURMUR',
    time: '0:42',
    author: 'Miki Chen',
    handle: 'did:plc:miki',
    body: '把身分握在自己手裡，不是為了變成錢包，而是讓每一次發文都能確定來自我。',
    stats: '8 replies · 31 resonance',
    tone: 'murmur',
  },
  {
    source: 'FROM A FOLLOW',
    type: 'NOTE',
    time: '12:08',
    author: 'Ting Wang',
    handle: 'did:plc:ting',
    body: 'Note 像個人版上的長一點發文。它可以被追蹤者看見，也能投射到板上形成討論。',
    stats: '14 replies · 52 resonance',
    tone: 'note',
  },
  {
    source: 'BOARD · #PHILOSOPHY',
    type: 'THREAD',
    time: '18:33',
    author: 'General board',
    handle: 'hosted board',
    body: '板不是首頁，板是你訂閱的公共討論空間。追蹤的人與訂閱的板會一起構成你的動態。',
    stats: '23 replies · 6 new',
    tone: 'board',
  },
];

const FOLLOWING_PEOPLE = ['Miki Chen', 'Ting Wang', 'Hiro Lin'];

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
            <p class="section-label">FEED · 動態</p>
            <h1 id="feed-title">你選擇看見的人與板</h1>
            <p>Elix 是重視身分的社群 App。功能重點是社群，身分工具在背後確保每則 Note、Murmur 與板上討論都能被驗證。</p>
          </div>
          <span class="permission-copy">${renderPermissionLabel(viewModel)}</span>
        </div>
        ${renderComposeCard(viewModel)}
        <nav class="feed-tabs" aria-label="Feed filters">
          <a aria-current="page" href="#/">動態</a>
          <a href="#/">追蹤</a>
          <a href="#/boards">板</a>
          <a href="#/">圈內</a>
        </nav>
        ${FEED_POSTS.map(renderFeedPost).join('')}
      </section>
      ${renderRightRail(boards)}
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
            <p class="section-label">BOARDS · 訂閱的板</p>
            <h1 id="boards-title">Boards</h1>
            <p>板是可訂閱的公共討論空間。訂閱後，板上的新 thread 會和追蹤者的 Note、Murmur 一起出現在 feed。</p>
          </div>
          <a class="primary-action" href="#/">Back to feed</a>
        </div>
        ${renderBoardDirectory(viewModel.boards ?? [], {
          title: 'Subscribed and available boards · 看板',
          emptyText: 'No boards are available.',
        })}
      </section>
      ${renderRightRail(viewModel.boards ?? [])}
    </section>
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
    <section class="cols" aria-labelledby="board-title">
      ${renderLeftRail(viewModel, 'boards')}
      <section class="feed board-detail" aria-labelledby="board-title">
        <section class="board-head" aria-labelledby="board-title">
          <div class="heading">
            <p class="section-label">BOARD · 討論板</p>
            <h1 id="board-title">${escapeHtml(boardTitle)}</h1>
            ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
            <p>這個板會作為 feed 的一個來源。你可以閱讀 thread，也可以把 Note 或 Murmur 延伸成板上的討論。</p>
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
            <span class="label-mono">BOARD ACTIVITY</span>
          </div>
          ${renderThreadList(threads)}
        </section>
      </section>
      ${renderRightRail(viewModel.boards ?? [])}
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

function renderComposeCard(viewModel) {
  const audience = viewModel.session?.authenticated ? '追蹤我的人 · 24' : '追蹤我的人 · 登入後可發布';
  const action = viewModel.actions?.showLogin
    ? '<a class="primary-action" href="#/login">Login to post</a>'
    : '<button class="primary-action" type="button" data-action="new-thread">Publish</button>';

  return `
    <section class="compose" aria-label="Create post">
      <div class="compose-prompt">
        <span class="avatar">E</span>
        <p>說點什麼。Murmur 是短發文，Note 是較完整的個人版發文；有追蹤你的人會在他們的 feed 上看到。</p>
      </div>
      <div class="compose-actions">
        <button type="button">Note</button>
        <button type="button">Murmur</button>
        <a href="#/boards">到板上發言</a>
        <span>${escapeHtml(audience)}</span>
        ${action}
      </div>
    </section>
  `;
}

function renderLeftRail(viewModel, active) {
  const navItems = [
    { id: 'feed', label: '動態', href: '#/' },
    { id: 'discover', label: '發現', href: '#/' },
    { id: 'notifications', label: '通知', href: '#/' },
    { id: 'circle', label: '圈內', href: '#/' },
    { id: 'boards', label: '論壇板', href: '#/boards' },
  ];

  return `
    <aside class="rail" aria-label="Elix navigation">
      <p class="rail-label">NAVIGATE</p>
      <nav class="rail-nav">
        ${navItems
          .map((item) => {
            const current = item.id === active ? ' aria-current="page"' : '';
            return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
          })
          .join('')}
      </nav>
      <div class="rail-block">
        <p class="rail-label">FOLLOWING</p>
        ${FOLLOWING_PEOPLE.map((name) => `<span>${escapeHtml(name)}</span>`).join('')}
      </div>
      <div class="rail-block">
        <p class="rail-label">SESSION</p>
        <span>${escapeHtml(viewModel.session?.authenticated ? shortIdentity(viewModel.session.subjectDid || viewModel.session.subject) : 'Anonymous')}</span>
      </div>
      <div class="rail-block">
        <p class="rail-label">RELAY</p>
        <span>${escapeHtml(viewModel.host?.displayName || 'Elix Relay')}</span>
      </div>
    </aside>
  `;
}

function renderRightRail(boards) {
  return `
    <aside class="right-rail" aria-label="Feed context">
      <section class="side-panel">
        <p class="section-label">CIRCLE · 圈</p>
        <h2>24 people follow you</h2>
        <p>你的 Note 與 Murmur 會先出現在追蹤者的動態裡。板上討論則依照訂閱流動。</p>
      </section>
      <section class="side-panel">
        <p class="section-label">SUBSCRIBED BOARDS</p>
        ${boards.length ? boards.slice(0, 4).map((board) => `<a href="#/boards/${encodeURIComponent(board.slug || board.id || '')}">#${escapeHtml(board.title || board.id)}</a>`).join('') : '<span>No boards yet</span>'}
      </section>
      <section class="side-note">
        動態是按時間排序的，沒有演算法決定你看見什麼。你看見的是你選擇看見的。
      </section>
    </aside>
  `;
}

function renderFeedPost(post) {
  return `
    <article class="post post-${escapeAttribute(post.tone)}">
      <div class="post-source">${escapeHtml(post.source)} · ${escapeHtml(post.type)} · ${escapeHtml(post.time)}</div>
      <div class="post-author">
        <span class="avatar">${escapeHtml(post.author.charAt(0))}</span>
        <div>
          <strong>${escapeHtml(post.author)}</strong>
          <span>${escapeHtml(post.handle)}</span>
        </div>
      </div>
      <p class="post-body">${escapeHtml(post.body)}</p>
      ${post.type === 'MURMUR' ? '<div class="murmur-player"><span></span><i></i><i></i><i></i></div>' : ''}
      <div class="post-actions">
        <button type="button">Reply</button>
        <button type="button">Resonate</button>
        <span>${escapeHtml(post.stats)}</span>
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
