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
import {
  REPORT_REASON_CODES,
  actionsForTargetKind,
} from './moderation_model.mjs';
import { renderQrCodeSvg } from './qr_code.mjs';
import { t } from './web_i18n.mjs';
import { TRUST_TIERS, meetsMinPostTier } from './web_session_client.mjs';

export function renderPageBody(viewModel, uiState = {}) {
  const pageId = viewModel?.page?.id ?? viewModel?.route?.pageId;

  switch (pageId) {
    case PAGE_IDS.home:
      return renderHome(viewModel, uiState);
    case PAGE_IDS.boards:
      return renderBoards(viewModel);
    case PAGE_IDS.board:
      return renderBoard(viewModel, uiState);
    case PAGE_IDS.login:
      return renderLogin(viewModel, uiState.login ?? {});
    case PAGE_IDS.sessions:
      return renderSessions(viewModel, uiState);
    case PAGE_IDS.moderation:
      return renderModeration(viewModel, uiState);
    default:
      return renderNotFound(viewModel);
  }
}

function renderHome(viewModel, uiState = {}) {
  const boards = viewModel.boards ?? [];
  const preferences = normalizeUiPreferences(uiState.preferences);

  return `
    ${renderError(viewModel.error)}
    <section class="cols social-home mobile-focus-home" aria-labelledby="feed-title">
      ${renderLeftRail(viewModel, 'feed')}
      <section class="feed focus-feed" aria-labelledby="feed-title">
        <div class="feed-head">
          <div>
            <p class="section-label">${escapeHtml(t('home.kicker'))}</p>
            <h1 id="feed-title">${escapeHtml(t('home.title'))}</h1>
            <p>${escapeHtml(t('home.subtitle'))}</p>
          </div>
          <span class="permission-copy">${renderPermissionLabel(viewModel)}</span>
        </div>
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
            <h1 id="board-title">${escapeHtml(boardTitle)}${gate.gated ? ` ${renderGateBadge()}` : ''}</h1>
            ${board.description ? `<p>${escapeHtml(board.description)}</p>` : ''}
            ${gate.gated ? `<p class="gate-requirement">${escapeHtml(t('board.gateRequirement', { tier: trustTierLabel(gate.requiredTier) }))}</p>` : ''}
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
      </section>
      ${renderRightRail(viewModel, viewModel.boards ?? [])}
    </section>
  `;
}

// The relay enforces posting gates at intent acceptance; this client-side
// check only makes the board's `posting_policy.min_post_tier` discoverable
// before the user tries to write.
function boardPostingGate(board, session) {
  const minPostTier = board?.postingPolicy?.minPostTier ?? null;
  const gated = minPostTier === TRUST_TIERS.verifiedHuman;
  const trustTier = session?.trustTier ?? TRUST_TIERS.anonymous;

  return {
    gated,
    requiredTier: minPostTier,
    blocked:
      gated && Boolean(session?.authenticated) && !meetsMinPostTier(trustTier, minPostTier),
  };
}

function renderGateBadge() {
  return `<span class="gate-badge">${escapeHtml(t('board.gateBadge'))}</span>`;
}

function renderBoardPostAction(viewModel, gate) {
  if (gate.blocked) {
    return `
      <div class="gate-blocked" role="note">
        <button class="primary-action" type="button" disabled>${escapeHtml(t('common.newThread'))}</button>
        <p>${escapeHtml(t('board.gateBlockedMessage', { tier: trustTierLabel(viewModel.session?.trustTier ?? TRUST_TIERS.anonymous) }))}</p>
      </div>
    `;
  }

  return viewModel.actions?.canCreateThread
    ? `<button class="primary-action" type="button" data-action="new-thread">${escapeHtml(t('common.newThread'))}</button>`
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

function renderMobileFocusStage(viewModel, boards, preferences) {
  const activeScene = preferences.activeScene;
  const showCoachmark = !preferences.coachmarkDismissed;

  return `
    <section class="mobile-focus-stage" data-active-scene="${escapeAttribute(activeScene)}" data-motion-mode="${escapeAttribute(preferences.motionMode)}" aria-label="${escapeAttribute(t('focus.mobileAria'))}">
      <div class="scene-switcher" role="tablist" aria-label="${escapeAttribute(t('focus.sceneSwitchAria'))}">
        ${renderSceneButton('personal', t('focus.personalScene'), activeScene)}
        ${renderSceneButton('forum', t('focus.forumScene'), activeScene)}
      </div>
      <p class="scene-help">${escapeHtml(t('focus.sceneHelp'))}</p>
      ${
        showCoachmark
          ? `<aside class="swipe-coachmark">
              <div>
                <p class="section-label">${escapeHtml(t('focus.coachmarkLabel'))}</p>
                <h3>${escapeHtml(t('focus.coachmarkTitle'))}</h3>
                <p>${escapeHtml(t('focus.coachmarkBody'))}</p>
              </div>
              <button type="button" data-action="dismiss-swipe-coachmark">${escapeHtml(t('focus.coachmarkDismiss'))}</button>
            </aside>`
          : ''
      }
      <div class="scene-viewport">
        <div class="scene-track">
          ${renderPersonalScene(viewModel, preferences)}
          ${renderForumScene(viewModel, boards, preferences)}
        </div>
      </div>
    </section>
  `;
}

function renderSceneButton(scene, label, activeScene) {
  const selected = scene === activeScene;
  return `
    <button type="button" class="scene-tab" data-action="select-scene" data-scene="${escapeAttribute(scene)}" role="tab" aria-selected="${selected ? 'true' : 'false'}">
      ${scene === 'personal' ? renderInlineMark() : ''}
      <span>${escapeHtml(label)}</span>
      <i aria-hidden="true"></i>
    </button>
  `;
}

function renderPersonalScene(viewModel, preferences) {
  const audience = viewModel.session?.authenticated ? t('home.signedBySession') : t('home.loginRequiredForPosting');

  return `
    <section class="scene-panel personal-scene" data-scene="personal" data-scene-theme="${escapeAttribute(preferences.personalTheme)}" aria-labelledby="personal-board-title">
      <div class="scene-meta-row">
        <span>${escapeHtml(t('focus.personal.date'))}</span>
        <span>${escapeHtml(t('focus.personal.week'))}</span>
      </div>
      <div class="personal-board-head">
        <div>
          <p class="section-label">${escapeHtml(t('focus.personalScene'))}</p>
          <h2 id="personal-board-title">${escapeHtml(t('focus.personal.title'))}</h2>
        </div>
        <span class="signed-pill">${escapeHtml(audience)}</span>
      </div>
      <div class="diary-list">
        ${renderDiaryEntry({ type: t('focus.diary.noteType'), when: t('focus.diary.noteWhen'), title: t('focus.diary.noteTitle'), body: t('focus.diary.noteBody'), kind: 'note' })}
        ${renderDiaryEntry({ type: t('focus.diary.murmurOneType'), when: t('focus.diary.murmurOneWhen'), body: t('focus.diary.murmurOneBody'), kind: 'murmur', player: true })}
        ${renderDiaryEntry({ type: t('focus.diary.murmurTwoType'), when: t('focus.diary.murmurTwoWhen'), body: t('focus.diary.murmurTwoBody'), kind: 'murmur' })}
      </div>
      <section class="ai-bridge-card" aria-label="${escapeAttribute(t('focus.aiBridgeAria'))}">
        <span class="ai-dot-inline">${renderAiGlyph()}</span>
        <div>
          <p class="section-label">${escapeHtml(t('focus.aiBridgeLabel'))}</p>
          <h3>${escapeHtml(t('focus.aiBridgeTitle'))}</h3>
          <p>${escapeHtml(t('focus.aiBridgeBody'))}</p>
        </div>
      </section>
      <button class="mobile-compose-fab" type="button" aria-label="${escapeAttribute(t('focus.composeAria'))}">+</button>
    </section>
  `;
}

function renderForumScene(viewModel, boards, preferences) {
  return `
    <section class="scene-panel forum-scene" data-scene="forum" data-scene-theme="${escapeAttribute(preferences.forumTheme)}" aria-labelledby="forum-board-title">
      <div class="scene-meta-row">
        <span>${escapeHtml(t('focus.forum.newToday'))}</span>
        <span>${escapeHtml(t('focus.forum.sources'))}</span>
      </div>
      <div class="personal-board-head">
        <div>
          <p class="section-label">${escapeHtml(t('focus.forumScene'))}</p>
          <h2 id="forum-board-title">${escapeHtml(t('focus.forum.title'))}</h2>
        </div>
        <a class="scene-inline-action" href="#/boards">${escapeHtml(t('focus.forum.subscribeBoards'))}</a>
      </div>
      <div class="forum-list">
        ${renderFollowFeedPost()}
        ${renderRelayFeed(boards, viewModel)}
      </div>
    </section>
  `;
}

function renderDiaryEntry({ type, when, title, body, kind, player = false }) {
  return `
    <article class="diary-entry">
      <div class="diary-entry-meta">
        <span class="entry-pip is-${escapeAttribute(kind)}"></span>
        <span>${escapeHtml(type)}</span>
        <time>${escapeHtml(when)}</time>
      </div>
      ${title ? `<h3>${escapeHtml(title)}</h3>` : ''}
      ${player ? renderMurmurMiniPlayer() : ''}
      <p${kind === 'murmur' ? ' class="is-italic"' : ''}>${escapeHtml(body)}</p>
    </article>
  `;
}

function renderMurmurMiniPlayer() {
  return `
    <div class="murmur-mini-player" aria-label="${escapeAttribute(t('focus.murmurAudioAria'))}">
      <span class="play-dot">▶</span>
      <span class="waveform" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span>
      <span>0:38</span>
    </div>
  `;
}

function renderFollowFeedPost() {
  return `
    <article class="post social-post">
      <div class="post-source">${escapeHtml(t('focus.follow.source'))}</div>
      <div class="post-author">
        <span class="avatar">M</span>
        <div>
          <strong>Mira Lin ${renderSignedPill(t('focus.passkeyCompact'))}</strong>
          <span>${escapeHtml(t('focus.follow.timestamp'))}</span>
        </div>
      </div>
      <p class="post-body">${escapeHtml(t('focus.follow.body'))}</p>
      <div class="post-actions">
        <button type="button">${escapeHtml(t('focus.follow.resonate'))}</button>
        <button type="button">${escapeHtml(t('common.reply'))}</button>
        ${renderSignedPill(t('focus.signedPasskey'))}
      </div>
    </article>
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

  if (viewModel.session?.authenticated) {
    navItems.push({
      id: 'moderation',
      label: t('common.moderation'),
      href: '#/moderation',
    });
  }
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
  const gated = board.postingPolicy?.minPostTier === TRUST_TIERS.verifiedHuman;

  return `
    <li>
      <a href="${escapeAttribute(href)}">${escapeHtml(title)}${gated ? ` ${renderGateBadge()}` : ''}</a>
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
  const title = thread.title || thread.subject || t('common.threadFallback');
  const author = thread.authorDid || thread.subjectDid || thread.author || null;
  const signed = Boolean(author);
  const initial = title.trim().charAt(0).toUpperCase() || 'T';
  const locked = Boolean(thread.locked);
  const posts = thread.posts ?? [];
  const threadId = thread.id ?? '';
  const authenticated = Boolean(context.session?.authenticated);

  return `
    <li${signed ? ' class="signed"' : ''}${locked ? ' data-locked="true"' : ''}>
      <div class="av">${escapeHtml(initial)}</div>
      <div>
        <h4 class="ttl">${escapeHtml(title)}${locked ? ` ${renderLockedBadge()}` : ''}</h4>
        <p class="author">${escapeHtml(shortIdentity(author))}${signed ? ` ${renderSignedPill(t('focus.passkeyCompact'))}` : ''}</p>
        ${locked ? renderLockedBanner(thread.lockReasonCode) : ''}
        ${posts.length ? renderThreadPosts(posts, context) : ''}
        ${renderThreadActions({ thread, context, locked, authenticated, threadId })}
      </div>
      <div class="meta">
        <span class="replies">${escapeHtml(t('board.replyCount', { count: thread.replyCount ?? thread.replies ?? 0 }))}</span>
        <span class="ago">${escapeHtml(thread.updatedAt ? formatExpiry(thread.updatedAt) : t('common.recent'))}</span>
      </div>
    </li>
  `;
}

function renderThreadActions({ context, locked, authenticated, threadId }) {
  // Constitution Base Rule 6: lock state is visible and reason-coded; a
  // locked thread accepts no new replies, so the reply affordance disappears.
  const reply = locked
    ? `<span class="locked-no-reply">${escapeHtml(t('moderation.lockedNoReply'))}</span>`
    : context.canReply
      ? `<button type="button" class="thread-reply">${escapeHtml(t('common.reply'))}</button>`
      : '';
  const report = authenticated
    ? renderReportControl({
        targetKind: 'thread',
        targetRef: threadId,
        boardId: context.boardId ?? '',
      })
    : '';

  if (!reply && !report) return '';

  return `<div class="thread-actions">${reply}${report}</div>`;
}

function renderThreadPosts(posts, context = {}) {
  return `
    <ul class="thread-posts">
      ${posts.map((post) => renderThreadPost(post, context)).join('')}
    </ul>
  `;
}

function renderThreadPost(post, context = {}) {
  if (post.removed) {
    return `
      <li class="thread-post is-removed">
        ${renderRemovedTombstone(post.reasonCode)}
      </li>
    `;
  }

  const authenticated = Boolean(context.session?.authenticated);

  return `
    <li class="thread-post">
      <p class="post-body">${escapeHtml(post.body ?? '')}</p>
      ${
        authenticated
          ? renderReportControl({
              targetKind: 'post',
              targetRef: post.id ?? '',
              boardId: context.boardId ?? '',
            })
          : ''
      }
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

function renderInlineMark() {
  return `
    <svg class="inline-elix-mark" viewBox="-100 -100 200 200" aria-hidden="true" focusable="false">
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

function renderAiGlyph() {
  return `
    <svg viewBox="0 0 22 22" aria-hidden="true" focusable="false">
      <path d="M11 3 L12.4 7.5 L16.9 8.9 L12.4 10.3 L11 14.8 L9.6 10.3 L5.1 8.9 L9.6 7.5 Z M17 14 L17.6 15.8 L19.4 16.4 L17.6 17 L17 18.8 L16.4 17 L14.6 16.4 L16.4 15.8 Z" />
    </svg>
  `;
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
