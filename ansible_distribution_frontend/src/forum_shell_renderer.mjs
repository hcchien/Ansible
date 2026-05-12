import { shortIdentity, trustTierLabel } from './forum_ui_text.mjs';

export function renderAppShell({ viewModel, bodyHtml }) {
  return `
    <div class="forum-shell">
      ${renderCommandHeader(viewModel)}
      <main class="forum-main" aria-labelledby="page-title">
        <div class="page-heading">
          <p class="section-label">${escapeHtml(pageKicker(viewModel))}</p>
          <h1 id="page-title">${escapeHtml(viewModel.page.title)}</h1>
          <p>${escapeHtml(pageIntro(viewModel))}</p>
        </div>
        ${bodyHtml}
      </main>
      ${renderAppFooter(viewModel)}
      ${renderMobileTabBar(viewModel)}
    </div>
  `;
}

export function renderCommandHeader(viewModel) {
  const hostLabel = viewModel.host?.displayName || 'Forum Relay';
  const nav = viewModel.navigation
    .map((item) => {
      const current = item.id === viewModel.page.id ? ' aria-current="page"' : '';
      return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
    })
    .join('');

  return `
    <header class="command-header">
      <a class="brand-lockup" href="#/" aria-label="Elix forum home">
        ${renderElixMark()}
        <span class="brand-word">Elix</span>
        <span class="brand-host">${escapeHtml(hostLabel)}</span>
      </a>
      <nav class="command-nav" aria-label="Forum">${nav}</nav>
      <div class="command-context">
        <span class="route-title">${escapeHtml(viewModel.page.title)}</span>
        ${renderSessionChip(viewModel.session)}
        ${renderPrimaryAction(viewModel)}
      </div>
    </header>
  `;
}

export function renderElixMark() {
  return `
    <svg class="elix-mark" viewBox="-100 -100 200 200" aria-hidden="true" focusable="false">
      <g transform="rotate(30)">
        <path d="M -60 40 L 60 40 M -60 40 L 0 -60 M 60 40 L 0 -60" />
        <circle cx="-60" cy="40" r="14" />
        <circle cx="60" cy="40" r="14" />
        <circle cx="0" cy="-60" r="14" />
        <circle class="elix-mark__center" cx="0" cy="6" r="8" />
      </g>
    </svg>
  `;
}

export function renderSessionChip(session) {
  if (!session?.authenticated) {
    return '<a class="session-chip is-anonymous" href="#/login"><span>Anonymous</span><strong>Read only</strong></a>';
  }

  return `
    <a class="session-chip is-authenticated" href="#/sessions">
      <span>${escapeHtml(shortIdentity(session.subjectDid || session.subject))}</span>
      <strong>${escapeHtml(trustTierLabel(session.trustTier))}</strong>
    </a>
  `;
}

export function renderPrimaryAction(viewModel) {
  if (viewModel.actions?.canRevokeSession && viewModel.page.id === 'sessions') {
    return '<button class="header-action is-danger" type="button" data-action="revoke-session">Revoke</button>';
  }

  if (viewModel.actions?.canCreateThread && viewModel.page.id === 'board') {
    return '<button class="header-action" type="button" data-action="new-thread">New thread</button>';
  }

  if (viewModel.actions?.showLogin) {
    return '<a class="header-action" href="#/login">Sign in</a>';
  }

  return '';
}

function pageKicker(viewModel) {
  switch (viewModel.page?.id) {
    case 'home':
      return 'FORUM HOST · 論壇主機';
    case 'boards':
      return 'BOARD DIRECTORY · 討論板目錄';
    case 'board':
      return 'BOARD · 討論板';
    case 'login':
      return 'APP-MEDIATED SESSION · 由 APP 中介';
    case 'sessions':
      return 'CURRENT SESSION · 當前工作階段';
    default:
      return 'ROUTE · 路徑';
  }
}

function pageIntro(viewModel) {
  switch (viewModel.page?.id) {
    case 'home':
      return 'Public reading stays open. Posting is signed from your app or passkey-backed session.';
    case 'boards':
      return 'Browse public boards hosted by this relay, then open the board that matches the conversation you want.';
    case 'board':
      return viewModel.board?.description || 'Read current threads and create a signed thread when your session has permission.';
    case 'login':
      return 'The browser never receives your keys. Start a challenge here, then approve it from the Elix app.';
    case 'sessions':
      return 'This web session is scoped to this browser. You can inspect its rights and revoke it at any time.';
    default:
      return 'Return to the forum host or board directory to keep reading.';
  }
}

function renderAppFooter(viewModel) {
  const hostLabel = viewModel.host?.displayName || 'Forum Relay';
  const pageLabel = viewModel.page?.id === 'sessions'
    ? shortFooterIdentity(viewModel.session?.subjectDid || viewModel.session?.subject)
    : hostLabel;

  return `
    <footer class="app-footer">
      <span>Elix · local-first forum access</span>
      <span>${escapeHtml(pageLabel)}</span>
    </footer>
  `;
}

function renderMobileTabBar(viewModel) {
  const items = [
    { id: 'home', label: 'Home', href: '#/', icon: renderElixMark() },
    { id: 'boards', label: 'Boards', href: '#/boards', icon: renderBoardIcon() },
    {
      id: viewModel.session?.authenticated ? 'sessions' : 'login',
      label: viewModel.session?.authenticated ? 'You' : 'Login',
      href: viewModel.session?.authenticated ? '#/sessions' : '#/login',
      icon: renderUserIcon(),
    },
  ];

  return `
    <nav class="mobile-tabbar" aria-label="Mobile forum navigation">
      ${items
        .map((item) => {
          const current = item.id === viewModel.page?.id ? ' aria-current="page"' : '';
          return `<a class="mobile-tab" href="${item.href}"${current}>${item.icon}<span>${item.label}</span></a>`;
        })
        .join('')}
    </nav>
  `;
}

function renderBoardIcon() {
  return `
    <svg class="mobile-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false">
      <rect x="3.5" y="3.5" width="13" height="13" rx="2" />
      <path d="M 6.5 7.5 H 13.5 M 6.5 10 H 13.5 M 6.5 12.5 H 11" />
    </svg>
  `;
}

function renderUserIcon() {
  return `
    <svg class="mobile-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false">
      <circle cx="10" cy="7.5" r="3" />
      <path d="M 4.5 16 C 5.4 12.9 7.2 11.4 10 11.4 C 12.8 11.4 14.6 12.9 15.5 16" />
    </svg>
  `;
}

function shortFooterIdentity(identity) {
  const value = String(identity ?? '');
  if (!value) return 'Anonymous';
  if (value.length <= 18) return value;
  return `${value.slice(0, 10)}...${value.slice(-4)}`;
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll('`', '&#96;');
}
