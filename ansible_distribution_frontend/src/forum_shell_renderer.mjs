import { shortIdentity, trustTierLabel } from './forum_ui_text.mjs';
import { icon } from './icons.mjs';
import { getCurrentLocale, t } from './web_i18n.mjs';

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
      ${renderMobileComposeFab(viewModel)}
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

/// Top bar — the design's `wtop`: brand lockup, a centered search field, and
/// a context cluster on the right. Primary navigation lives in the left rail
/// (desktop/tablet) and the bottom tab bar (mobile), matching the mockups;
/// the nav links stay in the DOM for rail-less pages, where CSS reveals them.
export function renderCommandHeader(viewModel) {
  const hostLabel = viewModel.host?.displayName || t('common.relay');
  const guest = !viewModel.session?.authenticated;
  const nav = viewModel.navigation
    .map((item) => {
      const current = item.id === viewModel.page.id ? ' aria-current="page"' : '';
      return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
    })
    .join('');

  return `
    <header class="command-header topbar wtop">
      <a class="brand-lockup" href="#/" aria-label="${escapeAttribute(t('common.elixHomeAria'))}">
        ${renderElixMark()}
        <span class="brand-word">Elix</span>
        <span class="brand-host">${escapeHtml(t('common.socialIdentity'))}</span>
      </a>
      <div class="searchbox" role="search" aria-label="${escapeAttribute(t('common.searchAria'))}">
        ${icon('search', 16)}
        <span>${escapeHtml(t('common.searchPlaceholder'))}</span>
      </div>
      <div class="command-context">
        <nav class="command-nav" aria-label="${escapeAttribute(t('common.navAria'))}">${nav}</nav>
        <span class="route-title">${escapeHtml(hostLabel)}</span>
        ${guest ? '' : renderBellButton(viewModel)}
        ${renderSessionChip(viewModel.session)}
        ${guest ? `<a class="btn-signin" href="#/login">${escapeHtml(t('common.login'))}</a>` : ''}
        ${renderPrimaryAction(viewModel)}
      </div>
    </header>
  `;
}

/// Notification truth is projected in this browser from verified forum feeds;
/// the Relay never receives read receipts.
function renderBellButton(viewModel) {
  const unreadCount = viewModel.notifications?.unreadCount ?? 0;
  const unreadClass = unreadCount > 0 ? ' has-unread' : '';
  const badge = unreadCount > 0
    ? `<span class="notification-badge" aria-hidden="true">${unreadCount > 99 ? '99+' : unreadCount}</span>`
    : '';
  return `<a class="icon-btn notification-button${unreadClass}" href="#/notifications" aria-label="${escapeAttribute(t('home.notifications'))}">${icon('bell', 17)}${badge}</a>`;
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
  // Guests get the design's ghost pill; signed-in sessions get the chip with
  // an avatar disc, handle, and trust tier.
  if (!session?.authenticated) {
    return `<span class="ghost-pill session-chip is-anonymous" aria-label="${escapeAttribute(t('common.session'))}"><span>${escapeHtml(t('common.anonymous'))}</span><strong>${escapeHtml(t('common.readOnly'))}</strong></span>`;
  }

  const identity = shortIdentity(session.subjectDid || session.subject);
  return `
    <a class="session-chip is-authenticated" href="#/sessions">
      <span class="av" aria-hidden="true">${escapeHtml(sessionInitial(identity))}</span>
      <span class="who">${escapeHtml(identity)}</span>
      <strong class="tier">${escapeHtml(trustTierLabel(session.trustTier))}</strong>
    </a>
  `;
}

function sessionInitial(identity) {
  const value = String(identity ?? '').replace(/^did:[a-z]+:/i, '');
  const first = [...value].find((char) => /\S/.test(char));
  return (first ?? 'E').toUpperCase();
}

export function renderPrimaryAction(viewModel) {
  if (viewModel.actions?.canRevokeSession && viewModel.page.id === 'sessions') {
    return `<button class="header-action is-danger" type="button" data-action="revoke-session">${escapeHtml(t('common.revoke'))}</button>`;
  }

  if (viewModel.actions?.canCreateThread && viewModel.page.id === 'board') {
    const boardId = viewModel.board?.id || viewModel.board?.slug || viewModel.route?.params?.boardId || '';
    const boardAttribute = boardId ? ` data-board-id="${escapeAttribute(boardId)}"` : '';
    return `<button class="header-action" type="button" data-action="new-thread"${boardAttribute}>${escapeHtml(t('common.newThread'))}</button>`;
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
      <span><a href="#/about">${escapeHtml(t('common.aboutElix'))}</a> · <a href="${escapeAttribute(legalHref('/support'))}">${escapeHtml(t('common.support'))}</a> · <a href="${escapeAttribute(legalHref('/privacy'))}">${escapeHtml(t('common.privacyPolicy'))}</a> · <a href="${escapeAttribute(legalHref('/terms'))}">${escapeHtml(t('common.termsOfService'))}</a></span>
      <span>${escapeHtml(pageLabel)}</span>
    </footer>
  `;
}

function legalHref(path) {
  return `${path}?lang=${encodeURIComponent(getCurrentLocale())}`;
}

/// Bottom tab bar (mobile) — the handoff's four equal cells:
/// 動態 · 發現 · 通知 · 你. Compose is a separate floating action, so the
/// navigation remains calm and the primary action never impersonates a tab.
/// Destinations without a route yet render as disabled cells rather than
/// dead links.
function renderMobileTabBar(viewModel) {
  const authenticated = Boolean(viewModel.session?.authenticated);
  const items = [
    { id: 'home', label: t('common.feed'), href: '#/', glyph: 'home' },
    { id: 'boards', label: t('common.boards'), href: '#/boards', glyph: 'search' },
    {
      id: 'notifications',
      label: t('home.notifications'),
      href: '#/notifications',
      glyph: 'bell',
      unreadCount: viewModel.notifications?.unreadCount ?? 0,
    },
    {
      id: authenticated ? 'sessions' : 'login',
      label: authenticated ? t('common.you') : t('common.login'),
      href: authenticated ? '#/sessions' : '#/login',
      glyph: 'eye',
    },
  ];

  return `
    <nav class="mobile-tabbar mtabbar" aria-label="${escapeAttribute(t('common.mobileNavAria'))}">
      ${items.map((item) => renderMobileTab(item, viewModel)).join('')}
    </nav>
  `;
}

function renderMobileTab(item, viewModel) {
  const label = escapeHtml(item.label);
  const glyph = icon(item.glyph, 24, 'mobile-icon');

  if (item.upcoming) {
    return `<span class="mobile-tab is-upcoming" aria-disabled="true" title="${escapeAttribute(t('common.comingSoon'))}">${glyph}<span>${label}</span></span>`;
  }

  const current = item.id === viewModel.page?.id ? ' aria-current="page"' : '';
  const unreadClass = item.unreadCount > 0 ? ' has-unread' : '';
  const badge = item.unreadCount > 0
    ? '<span class="mobile-notification-dot" aria-hidden="true"></span>'
    : '';
  return `<a class="mobile-tab${unreadClass}" href="${escapeAttribute(item.href)}"${current}>${glyph}${badge}<span>${label}</span></a>`;
}

/// The handoff puts compose above the mobile navigation as a round FAB.
/// It retains the existing login / signed-publication behavior.
function renderMobileComposeFab(viewModel) {
  if (viewModel.page?.id !== 'home') return '';
  const label = escapeAttribute(t('common.createPostAria'));
  const glyph = icon('plus', 23, 'mobile-icon');

  if (viewModel.actions?.showLogin || !viewModel.session?.authenticated) {
    return `<a class="mobile-compose-fab" href="#/login" aria-label="${label}">${glyph}</a>`;
  }

  const boardId = viewModel.board?.id || viewModel.board?.slug || viewModel.boards?.[0]?.id || viewModel.boards?.[0]?.slug || '';
  const boardAttribute = boardId ? ` data-board-id="${escapeAttribute(boardId)}"` : '';
  return `<button class="mobile-compose-fab" type="button" data-action="new-thread"${boardAttribute} aria-label="${label}">${glyph}</button>`;
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
