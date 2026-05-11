import { shortIdentity, trustTierLabel } from './forum_ui_text.mjs';

export function renderAppShell({ viewModel, bodyHtml }) {
  return `
    <div class="forum-shell">
      ${renderCommandHeader(viewModel)}
      <main class="forum-main" aria-labelledby="page-title">
        <div class="page-heading">
          <p class="section-label">${escapeHtml(viewModel.page.id)}</p>
          <h1 id="page-title">${escapeHtml(viewModel.page.title)}</h1>
        </div>
        ${bodyHtml}
      </main>
    </div>
  `;
}

export function renderCommandHeader(viewModel) {
  const label = viewModel.host?.displayName || 'Forum Relay';
  const nav = viewModel.navigation
    .map((item) => {
      const current = item.id === viewModel.page.id ? ' aria-current="page"' : '';
      return `<a href="${escapeAttribute(item.href)}"${current}>${escapeHtml(item.label)}</a>`;
    })
    .join('');

  return `
    <header class="command-header">
      <a class="brand-lockup" href="#/">${escapeHtml(label)}</a>
      <nav class="command-nav" aria-label="Forum">${nav}</nav>
      <div class="command-context">
        <span class="route-title">${escapeHtml(viewModel.page.title)}</span>
        ${renderSessionChip(viewModel.session)}
        ${renderPrimaryAction(viewModel)}
      </div>
    </header>
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
