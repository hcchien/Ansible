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
      return renderHome(viewModel, uiState);
    case PAGE_IDS.boards:
      return renderBoards(viewModel);
    case PAGE_IDS.board:
      return renderBoard(viewModel);
    case PAGE_IDS.login:
      return renderLogin(viewModel, uiState.login ?? {});
    case PAGE_IDS.sessions:
      return renderSessions(viewModel, uiState);
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

function renderSessions(viewModel, uiState = {}) {
  const session = viewModel.session ?? {};
  const scopes = session.scopes ?? [];
  const preferences = normalizeUiPreferences(uiState.preferences);
  const identity = shortIdentity(session.subjectDid || session.subject) || t('sessions.titleFallback');

  return `
    ${renderError(viewModel.error)}
    <section class="settings-home" aria-labelledby="settings-title">
      <div class="settings-topbar">
        <span></span>
        <p id="settings-title" class="settings-title">Settings</p>
        <a href="#/" class="settings-done">完成</a>
      </div>

      <section class="settings-identity-hero" aria-label="本機身分">
        <span class="settings-avatar" aria-hidden="true">${renderUserGlyph()}</span>
        <div>
          <h2>本機身分</h2>
          <p>本機 DID · ${escapeHtml(identity)} · ${escapeHtml(trustTierLabel(session.trustTier))}</p>
        </div>
        <span class="settings-edit">編輯</span>
      </section>

      ${renderSettingsGroup('身分與裝置 · IDENTITY', [
        renderSettingsRow({ icon: renderWalletGlyph(), title: '皮夾', code: 'WALLET', detail: '尚無憑證', value: '空' }),
        renderSettingsRow({ icon: renderSyncGlyph(), title: '同步', code: 'SYNC', detail: 'Forum Host / Nostr relay 設定', value: '設定' }),
        renderSettingsRow({ icon: renderShieldGlyph(), title: '存取與審計', code: 'ADMIN', detail: '誰看見了哪一個我', value: '0 可疑' }),
        renderSettingsRow({ icon: '文', title: '語言', code: 'LANGUAGE', detail: '選擇 app 介面語言', value: '繁體中文' }),
      ])}

      ${renderSettingsGroup('日常 · DAILY', [
        renderSettingsRow({ icon: renderBellGlyph(), title: '收信', code: 'INBOX', detail: '圈內回覆、新成員、同步', value: '0' }),
        renderSettingsRow({ icon: renderNoticeGlyph(), title: '通知', code: 'NOTIFICATIONS', detail: '決定哪些事會打擾你', value: '輕' }),
        renderSettingsRow({ icon: 'A', title: '閱讀偏好', code: 'READING', detail: '字級、行距、每版的光', value: '預設' }),
      ])}

      <section class="settings-preferences" aria-label="介面與語言">
        <p class="settings-group-label">介面與語言 · INTERFACE</p>
        <div class="settings-preference-block">
          <div class="settings-copy">
            <p class="section-label">每版的光</p>
            <h3>個人版可以是 Ink，討論區可以是 Paper。</h3>
            <p>只能在 Paper / Ink / Auto 之間調整，避免品牌散掉；圈內跟著個人版。</p>
          </div>
          <div class="theme-settings-grid">
            ${renderSceneThemePicker('personal', '個人版', preferences.personalTheme)}
            ${renderSceneThemePicker('forum', '討論區', preferences.forumTheme)}
          </div>
        </div>
        <div class="settings-preference-block">
          <div class="settings-copy">
            <p class="section-label">換版的動態</p>
            <h3>翻書，而不是滑窗。</h3>
            <p>尊重 reduced-motion；系統減少動態時會降回平移。</p>
          </div>
          <div class="motion-options">
            ${renderMotionOption('slide', '輕 · 平移', '兩張紙左右平移，沒有立體感。', preferences.motionMode)}
            ${renderMotionOption('book', '中 · 翻書', '兩個版像書的左右頁，輕微 perspective。', preferences.motionMode)}
            ${renderMotionOption('cube', '深 · 翻立方', '較強烈，給喜歡明顯空間感的人。', preferences.motionMode)}
          </div>
        </div>
      </section>

      ${renderSettingsGroup('邊界 · BOUNDARIES', [
        renderSettingsRow({ icon: renderKeyGlyph(), title: '備份與還原', code: 'RECOVERY', detail: 'passphrase、新裝置遷移', value: '未設', tone: 'danger' }),
        renderSettingsRow({ icon: renderBlockedGlyph(), title: '封鎖名單', code: 'BLOCKED', detail: '你選擇不再看見的人', value: '0' }),
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

      <p class="settings-version">Elix · 0.4.1 · 本地優先</p>
    </section>
  `;
}

function renderMobileFocusStage(viewModel, boards, preferences) {
  const activeScene = preferences.activeScene;
  const showCoachmark = !preferences.coachmarkDismissed;

  return `
    <section class="mobile-focus-stage" data-active-scene="${escapeAttribute(activeScene)}" data-motion-mode="${escapeAttribute(preferences.motionMode)}" aria-label="Elix Mobile Focus">
      <div class="scene-switcher" role="tablist" aria-label="場景切換">
        ${renderSceneButton('personal', '個人版', activeScene)}
        ${renderSceneButton('forum', '討論區', activeScene)}
      </div>
      <p class="scene-help">往左滑，或點「討論區」切到公開場景；點「個人版」回到自己的版。</p>
      ${
        showCoachmark
          ? `<aside class="swipe-coachmark">
              <div>
                <p class="section-label">一個小技巧</p>
                <h3>這裡是你的個人版。</h3>
                <p>想看別人？往左滑，或是點上面的「討論區」。</p>
              </div>
              <button type="button" data-action="dismiss-swipe-coachmark">知道了</button>
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
        <span>2026.05.23 SAT</span>
        <span>本週 · THIS WEEK</span>
      </div>
      <div class="personal-board-head">
        <div>
          <p class="section-label">個人版</p>
          <h2 id="personal-board-title">你寫下的 Note 與 Murmur</h2>
        </div>
        <span class="signed-pill">${escapeHtml(audience)}</span>
      </div>
      <div class="diary-list">
        ${renderDiaryEntry({ type: 'NOTE · 4 段', when: '昨 14:36', title: '關於信任的地形', body: '信任不是 default-on，也不是一個開關。它更像是一種地形，有山谷、有稜線、有路徑要慢慢被踩出來。', kind: 'note' })}
        ${renderDiaryEntry({ type: 'MURMUR · 0:38', when: '昨 22:08', body: '「default-on 是誰的預設？我們是不是都默許了什麼自己其實沒同意 …」', kind: 'murmur', player: true })}
        ${renderDiaryEntry({ type: 'MURMUR · 1:14', when: '前天', body: '「鑰匙這個詞比帳號好，因為鑰匙是會被傳下去的 …」', kind: 'murmur' })}
      </div>
      <section class="ai-bridge-card" aria-label="AI bridge">
        <span class="ai-dot-inline">${renderAiGlyph()}</span>
        <div>
          <p class="section-label">AI · 橫向橋</p>
          <h3>從過去的 murmur 找材料，編入現在的 note。</h3>
          <p>只在本機整理。不會用來訓練，不會離開這台裝置。</p>
        </div>
      </section>
      <button class="mobile-compose-fab" type="button" aria-label="新增 Note 或 Murmur">+</button>
    </section>
  `;
}

function renderForumScene(viewModel, boards, preferences) {
  return `
    <section class="scene-panel forum-scene" data-scene="forum" data-scene-theme="${escapeAttribute(preferences.forumTheme)}" aria-labelledby="forum-board-title">
      <div class="scene-meta-row">
        <span>42 新 · 今</span>
        <span>追蹤 / 訂閱的板</span>
      </div>
      <div class="personal-board-head">
        <div>
          <p class="section-label">討論區</p>
          <h2 id="forum-board-title">追蹤的人與訂閱的板</h2>
        </div>
        <a class="scene-inline-action" href="#/boards">訂閱板</a>
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
    <div class="murmur-mini-player" aria-label="Murmur audio preview">
      <span class="play-dot">▶</span>
      <span class="waveform" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span>
      <span>0:38</span>
    </div>
  `;
}

function renderFollowFeedPost() {
  return `
    <article class="post social-post">
      <div class="post-source">FROM A FOLLOW — 你在三月關注了 Mira</div>
      <div class="post-author">
        <span class="avatar">M</span>
        <div>
          <strong>Mira Lin ${renderSignedPill('✓ PK')}</strong>
          <span>@mira · 2h</span>
        </div>
      </div>
      <p class="post-body">翻到 2017 年的舊筆記：「當演算法決定你看見什麼，沈默就會變成默許。」八年後重新打字。</p>
      <div class="post-actions">
        <button type="button">共鳴</button>
        <button type="button">${escapeHtml(t('common.reply'))}</button>
        ${renderSignedPill('SIGNED · PASSKEY')}
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
    ['light', 'Paper'],
    ['dark', 'Ink'],
    ['auto', '跟隨系統'],
  ];

  return `
    <div class="scene-theme-picker" data-scene="${escapeAttribute(scene)}">
      <div class="scene-theme-head">
        <strong>${escapeHtml(label)}</strong>
        <span>${scene === 'personal' ? '寫給自己' : '白天的廣場'}</span>
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
        <p class="author">${escapeHtml(shortIdentity(author))}${signed ? ` ${renderSignedPill('✓ PK')}` : ''}</p>
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
