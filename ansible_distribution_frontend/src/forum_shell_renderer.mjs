import { shortIdentity, trustTierLabel } from './forum_ui_text.mjs';
import { t } from './web_i18n.mjs';

const DEFAULT_UI_PREFERENCES = Object.freeze({
  activeScene: 'personal',
  personalTheme: 'auto',
  forumTheme: 'auto',
  motionMode: 'book',
});

export function renderAppShell({ viewModel, bodyHtml, uiPreferences = DEFAULT_UI_PREFERENCES }) {
  const preferences = normalizeUiPreferences(uiPreferences);
  const pageId = viewModel?.page?.id ?? 'unknown';

  return `
    <div class="forum-shell" data-page-id="${escapeAttribute(pageId)}" data-active-scene="${escapeAttribute(preferences.activeScene)}" data-personal-theme="${escapeAttribute(preferences.personalTheme)}" data-forum-theme="${escapeAttribute(preferences.forumTheme)}" data-motion-mode="${escapeAttribute(preferences.motionMode)}">
      ${renderCommandHeader(viewModel)}
      <main class="forum-main">
        ${bodyHtml}
      </main>
      ${renderAppFooter(viewModel)}
      ${renderMobileTabBar(viewModel)}
    </div>
  `;
}

function normalizeUiPreferences(preferences = {}) {
  return {
    activeScene: preferences.activeScene === 'forum' ? 'forum' : 'personal',
    personalTheme: normalizeTheme(preferences.personalTheme),
    forumTheme: normalizeTheme(preferences.forumTheme),
    motionMode: ['slide', 'book', 'cube'].includes(preferences.motionMode)
      ? preferences.motionMode
      : 'book',
  };
}

function normalizeTheme(value) {
  return ['light', 'dark', 'auto'].includes(value) ? value : 'auto';
}

export function renderCommandHeader(viewModel) {
  const hostLabel = viewModel.host?.displayName || t('common.relay');
  const nav = viewModel.navigation
    .map((item) => {
      const current = item.id === viewModel.page.id ? ' aria-current="page"' : '';
      return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
    })
    .join('');

  return `
    <header class="command-header topbar">
      <a class="brand-lockup" href="#/" aria-label="${escapeAttribute(t('common.elixHomeAria'))}">
        ${renderElixMark()}
        <span class="brand-word">Elix</span>
        <span class="brand-host">${escapeHtml(t('common.socialIdentity'))}</span>
      </a>
      <div class="searchbox" role="search" aria-label="${escapeAttribute(t('common.searchAria'))}">
        <span>${escapeHtml(t('common.searchPlaceholder'))}</span>
      </div>
      <div class="command-context">
        <nav class="command-nav" aria-label="${escapeAttribute(t('common.navAria'))}">${nav}</nav>
        <span class="route-title">${escapeHtml(hostLabel)}</span>
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
    return `<span class="session-chip is-anonymous" aria-label="${escapeAttribute(t('common.session'))}"><span>${escapeHtml(t('common.anonymous'))}</span><strong>${escapeHtml(t('common.readOnly'))}</strong></span>`;
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
    return `<button class="header-action is-danger" type="button" data-action="revoke-session">${escapeHtml(t('common.revoke'))}</button>`;
  }

  if (viewModel.actions?.canCreateThread && viewModel.page.id === 'board') {
    return `<button class="header-action" type="button" data-action="new-thread">${escapeHtml(t('common.newThread'))}</button>`;
  }

  if (viewModel.actions?.showLogin) {
    return '';
  }

  return '';
}

function renderAppFooter(viewModel) {
  const hostLabel = viewModel.host?.displayName || t('common.relay');
  const pageLabel = viewModel.page?.id === 'sessions'
    ? shortFooterIdentity(viewModel.session?.subjectDid || viewModel.session?.subject)
    : hostLabel;

  return `
    <footer class="app-footer">
      <span>${escapeHtml(t('common.identityBackedSocialApp'))}</span>
      <span>${escapeHtml(pageLabel)}</span>
    </footer>
  `;
}

function renderMobileTabBar(viewModel) {
  const items = [
    { id: 'home', label: t('common.feed'), href: '#/', icon: renderElixMark() },
    { id: 'boards', label: t('common.boards'), href: '#/boards', icon: renderBoardIcon() },
    {
      id: viewModel.session?.authenticated ? 'sessions' : 'login',
      label: viewModel.session?.authenticated ? t('common.you') : t('common.login'),
      href: viewModel.session?.authenticated ? '#/sessions' : '#/login',
      icon: renderUserIcon(),
    },
  ];

  return `
    <nav class="mobile-tabbar" aria-label="${escapeAttribute(t('common.mobileNavAria'))}">
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
  if (!value) return t('common.anonymous');
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
