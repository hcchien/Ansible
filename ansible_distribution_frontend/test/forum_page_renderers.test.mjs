import assert from 'node:assert/strict';

import { CONTRACT_FIXTURES } from '../src/contract_fixtures.mjs';
import {
  normalizeForumHost,
  normalizeHostedBoard,
} from '../src/forum_data_adapter.mjs';
import { renderPageBody } from '../src/forum_page_renderers.mjs';
import {
  createFrontendFlowHarness,
  runBoardRouteFlow,
  runPublicHomeFlow,
} from '../src/integration_flow_harness.mjs';
import {
  applyModerationStateToThreads,
  groupReportsByBoard,
  normalizeModerationAction,
  normalizeModerationState,
  normalizeReport,
} from '../src/moderation_model.mjs';
import { PAGE_IDS, buildAppViewModel } from '../src/state_model.mjs';
import { setCurrentLocale } from '../src/web_i18n.mjs';

const homeHarness = createFrontendFlowHarness({ routeHash: '#/', sessionMode: 'anonymous' });
const homeState = await runPublicHomeFlow(homeHarness);
const homeHtml = renderPageBody(homeState.viewModel);
assert.match(homeHtml, /Local Forum Host/);
assert.match(homeHtml, /General/);
assert.match(homeHtml, /唯讀/);
assert.match(homeHtml, /Elix 是重視身分的社群 App/);
assert.match(homeHtml, /RELAY · BOARD · #general/);
assert.match(homeHtml, /打開看板/);
assert.match(homeHtml, /Note/);
assert.match(homeHtml, /登入後可簽署發文/);
assert.match(homeHtml, /class="cols social-home mobile-focus-home"/);
assert.match(homeHtml, /class="mobile-focus-stage"/);
assert.match(homeHtml, /data-scene="personal"/);
assert.match(homeHtml, /個人版/);
assert.match(homeHtml, /討論區/);
assert.match(homeHtml, /往左滑/);
assert.match(homeHtml, /class="mobile-compose-fab"/);
assert.match(homeHtml, /已訂閱看板/);
assert.doesNotMatch(homeHtml, /Mira Lin|FROM A FOLLOW|關於信任的地形|MURMUR · 0:38|AI · 橫向橋/);
assert.doesNotMatch(homeHtml, /工作階段/);
assert.doesNotMatch(homeHtml, /RELAY · 來源/);
assert.doesNotMatch(homeHtml, /Relay 資料/);
assert.doesNotMatch(homeHtml, /傳給圈內/);
assert.doesNotMatch(homeHtml, /App-approved web session login|Read only|Open board|Login required for signed posting/);

const boardHarness = createFrontendFlowHarness({
  routeHash: '#/boards/general',
  sessionMode: 'approvedDid',
});
const boardState = await runBoardRouteFlow(boardHarness);
const boardHtml = renderPageBody(boardState.viewModel);
assert.match(boardHtml, /General/);
assert.match(boardHtml, /新討論串/);
assert.match(boardHtml, /自持有 DID/);
assert.match(boardHtml, /class="board-head"/);
assert.match(boardHtml, /class="card thread-list"/);
assert.match(boardHtml, /BOARD ACTIVITY/);
assert.doesNotMatch(boardHtml, /New thread|Sign in to post|Self-custody DID/);
assert.doesNotMatch(boardHtml, /class="gate-badge"|真人驗證版/);

const gatedBoard = normalizeHostedBoard(CONTRACT_FIXTURES.forum.gatedBoard);
const gatedForum = {
  host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
  boards: [gatedBoard],
  board: gatedBoard,
  threads: [],
  capabilities: { canCreateThread: true, canReply: true },
};
const gatedRoute = { pageId: PAGE_IDS.board, params: { boardId: 'verified-humans' } };

const belowTierVm = buildAppViewModel({
  route: gatedRoute,
  session: {
    authenticated: true,
    trustTier: 'self_custody_did',
    subjectDid: 'did:plc:fixture',
    scopes: ['forum:read', 'forum:post'],
    capabilities: { canPost: true, canReply: true },
  },
  forum: gatedForum,
});
const belowTierHtml = renderPageBody(belowTierVm);
assert.match(belowTierHtml, /class="gate-badge"/);
assert.match(belowTierHtml, /真人驗證版/);
assert.match(belowTierHtml, /這個板需要「已驗證真人」層級才能發文/);
assert.match(belowTierHtml, /class="gate-blocked"/);
assert.match(belowTierHtml, /<button class="primary-action" type="button" disabled>/);
assert.match(belowTierHtml, /你目前的層級是「自持有 DID」/);
assert.match(belowTierHtml, /請在 Elix app 完成真人驗證/);
assert.doesNotMatch(belowTierHtml, /data-action="new-thread"/);

const verifiedHumanVm = buildAppViewModel({
  route: gatedRoute,
  session: {
    authenticated: true,
    trustTier: 'verified_human',
    subjectDid: 'did:plc:fixture',
    scopes: ['forum:read', 'forum:post'],
    capabilities: { canPost: true, canReply: true },
  },
  forum: gatedForum,
});
const verifiedHumanHtml = renderPageBody(verifiedHumanVm);
assert.match(verifiedHumanHtml, /class="gate-badge"/);
assert.match(verifiedHumanHtml, /這個板需要「已驗證真人」層級才能發文/);
assert.match(verifiedHumanHtml, /data-action="new-thread"/);
assert.doesNotMatch(verifiedHumanHtml, /class="gate-blocked"/);
assert.doesNotMatch(verifiedHumanHtml, /請在 Elix app 完成真人驗證/);

const anonymousGatedVm = buildAppViewModel({
  route: gatedRoute,
  session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
  forum: { ...gatedForum, capabilities: { canCreateThread: false, canReply: false } },
});
const anonymousGatedHtml = renderPageBody(anonymousGatedVm);
assert.match(anonymousGatedHtml, /class="gate-badge"/);
assert.match(anonymousGatedHtml, /這個板需要「已驗證真人」層級才能發文/);
assert.match(anonymousGatedHtml, /登入後發文/);
assert.doesNotMatch(anonymousGatedHtml, /class="gate-blocked"/);

const rejectedPostVm = buildAppViewModel({
  route: gatedRoute,
  session: {
    authenticated: true,
    trustTier: 'self_custody_did',
    subjectDid: 'did:plc:fixture',
    scopes: ['forum:read', 'forum:post'],
    capabilities: { canPost: true, canReply: true },
  },
  forum: gatedForum,
  error: CONTRACT_FIXTURES.errors.postingRequiresTier,
});
const rejectedPostHtml = renderPageBody(rejectedPostVm);
assert.match(rejectedPostHtml, /class="info-banner is-warning"/);
assert.match(rejectedPostHtml, /需要真人驗證/);
assert.match(rejectedPostHtml, /這個板需要「已驗證真人」層級才能發文。請在 Elix app 完成驗證後再試一次。/);

const gatedDirectoryVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.boards, params: {} },
  session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
  forum: { ...gatedForum, board: null },
});
const gatedDirectoryHtml = renderPageBody(gatedDirectoryVm);
assert.match(gatedDirectoryHtml, /class="gate-badge"/);
assert.match(gatedDirectoryHtml, /真人驗證版/);

const loginVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.login, params: {} },
  session: { authenticated: false, status: 'pending', scopes: [] },
  forum: null,
});
const loginHtml = renderPageBody(loginVm, {
  login: {
    status: 'pending',
    challenge: {
      challengeId: 'wsc_fixture',
      expiresAt: '2026-05-12T01:00:00Z',
      deepLink: 'trisaura://web-session/approve?challenge_id=wsc_fixture',
      qrPayload: 'trisaura://web-session/approve?challenge_id=wsc_fixture',
    },
    requestedScopes: ['forum:read', 'forum:post', 'forum:reply', 'identity:display'],
  },
});
assert.match(loginHtml, /用 Elix app 登入/);
assert.match(loginHtml, /wsc_fixture/);
assert.match(loginHtml, /發布討論串/);
assert.match(loginHtml, /class="login-grid"/);
assert.match(loginHtml, /class="challenge-payload-preview"/);
assert.match(loginHtml, /class="qr-code"/);
assert.match(loginHtml, /data-action="poll-login"/);
assert.doesNotMatch(loginHtml, /data-action="start-login"/);
assert.match(loginHtml, /身分留在 Elix app/);
assert.match(loginHtml, /用 Elix app 掃描/);
assert.match(loginHtml, /用 Elix app 掃描這個 QR code/);
assert.doesNotMatch(loginHtml, /登入挑戰|建立挑戰|有效挑戰|The key stays|Approving the challenge|App login challenge|Create challenge|Start app login/);
assert.doesNotMatch(loginHtml, /Deep link/);
assert.doesNotMatch(loginHtml, /QR payload/);
assert.doesNotMatch(loginHtml, /trisaura:\/\/web-session\/approve/);
assert.doesNotMatch(loginHtml, /Open in app/);

const unsafeLoginHtml = renderPageBody(loginVm, {
  login: {
    status: 'pending',
    challenge: {
      challengeId: 'wsc_unsafe',
      expiresAt: '2026-05-12T01:00:00Z',
      deepLink: 'javascript:alert(1)',
      qrPayload: 'javascript:alert(1)',
    },
    requestedScopes: ['forum:read'],
  },
});
assert.doesNotMatch(unsafeLoginHtml, /href="javascript:alert\(1\)"/);
assert.doesNotMatch(unsafeLoginHtml, /href="#"/);
assert.doesNotMatch(unsafeLoginHtml, /javascript:alert\(1\)/);

const sessionsVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.sessions, params: {} },
  session: {
    authenticated: true,
    subjectDid: 'did:plc:fixtureabcdef',
    trustTier: 'self_custody_did',
    scopes: ['forum:post', 'session:revoke'],
    expiresAt: '2026-05-12T01:00:00Z',
    capabilities: { canRevoke: true },
  },
  forum: null,
});
const sessionsHtml = renderPageBody(sessionsVm);
assert.match(sessionsHtml, /自持有 DID/);
assert.match(sessionsHtml, /發布討論串/);
assert.match(sessionsHtml, /撤銷目前工作階段/);
assert.match(sessionsHtml, /class="settings-home"/);
assert.match(sessionsHtml, /本機身分/);
assert.match(sessionsHtml, /身分與裝置/);
assert.match(sessionsHtml, /日常/);
assert.match(sessionsHtml, /邊界/);
assert.match(sessionsHtml, /介面與語言/);
assert.match(sessionsHtml, /每版的光/);
assert.match(sessionsHtml, /換版的動態/);
assert.match(sessionsHtml, /data-action="set-scene-theme"/);
assert.match(sessionsHtml, /data-action="set-motion-mode"/);
assert.match(sessionsHtml, /未設/);
assert.doesNotMatch(sessionsHtml, /Revoke current session|This browser session is scoped and revocable|Trust tier|Expiry/);

setCurrentLocale('en');

const englishHomeHtml = renderPageBody(homeState.viewModel);
assert.match(englishHomeHtml, /Available public sources/);
assert.match(englishHomeHtml, /Swipe left/);
assert.match(englishHomeHtml, /Forum/);
assert.match(englishHomeHtml, /Open board/);
assert.doesNotMatch(englishHomeHtml, /Mira Lin|FROM A FOLLOW|A terrain of trust|From past murmurs|個人版|討論區|往左滑|橫向橋|共鳴/);

const englishSessionsHtml = renderPageBody(sessionsVm);
assert.match(englishSessionsHtml, /Done/);
assert.match(englishSessionsHtml, /Local identity/);
assert.match(englishSessionsHtml, /Identity and devices/);
assert.match(englishSessionsHtml, /Interface and language/);
assert.match(englishSessionsHtml, /Local-first/);
assert.match(englishSessionsHtml, /Not set/);
assert.doesNotMatch(englishSessionsHtml, /完成|本機身分|身分與裝置|介面與語言|本地優先|未設/);

setCurrentLocale('zh-Hant');

const notFoundVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.notFound, params: { path: '/missing' } },
  session: { authenticated: false },
  forum: null,
});
assert.match(renderPageBody(notFoundVm), /路徑不可用/);
assert.doesNotThrow(() => renderPageBody(undefined));
assert.match(renderPageBody(undefined), /路徑不可用/);

// --- Reporting + moderation rendering ---

const generalBoard = normalizeHostedBoard(CONTRACT_FIXTURES.forum.boards[0]);
const moderatedThreads = applyModerationStateToThreads(
  [
    {
      id: 'thread-9',
      title: 'Reported thread',
      authorDid: 'did:plc:author',
      posts: [
        { id: 'post-101', body: 'removed body text' },
        { id: 'post-102', body: 'kept body text' },
      ],
    },
    {
      id: 'thread-1',
      title: 'Open thread',
      authorDid: 'did:plc:author',
      posts: [{ id: 'post-201', body: 'reportable post body' }],
    },
  ],
  normalizeModerationState(CONTRACT_FIXTURES.moderation.boardState),
);
const moderatedSession = {
  authenticated: true,
  trustTier: 'self_custody_did',
  subjectDid: 'did:plc:fixture',
  scopes: ['forum:read', 'forum:post', 'forum:reply'],
  capabilities: { canPost: true, canReply: true },
};
const moderatedBoardVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.board, params: { boardId: 'general' } },
  session: moderatedSession,
  forum: {
    host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
    boards: [generalBoard],
    board: generalBoard,
    threads: moderatedThreads,
    capabilities: { canCreateThread: true, canReply: true },
  },
});
const moderatedBoardHtml = renderPageBody(moderatedBoardVm);

// Removed-post tombstone: reason-coded, content stripped.
assert.match(moderatedBoardHtml, /class="post-tombstone"/);
assert.match(moderatedBoardHtml, /已自此看板移除 · 垃圾訊息/);
assert.doesNotMatch(moderatedBoardHtml, /removed body text/);
assert.match(moderatedBoardHtml, /kept body text/);

// Locked-thread banner with reason; reply affordance disappears on lock.
assert.match(moderatedBoardHtml, /class="locked-banner"/);
assert.match(moderatedBoardHtml, /討論串已鎖定 · 騷擾/);
assert.match(moderatedBoardHtml, /class="locked-badge"/);
assert.match(moderatedBoardHtml, /鎖定中的討論串不接受新回覆/);
assert.match(moderatedBoardHtml, /class="thread-reply"/);
const lockedItemHtml = moderatedBoardHtml.slice(
  moderatedBoardHtml.indexOf('Reported thread'),
  moderatedBoardHtml.indexOf('Open thread'),
);
assert.doesNotMatch(lockedItemHtml, /class="thread-reply"/);

// Signed-in report picker: reason enum + note field + required-note hint.
assert.match(moderatedBoardHtml, /data-action="submit-report"/);
assert.match(moderatedBoardHtml, /data-target-kind="thread" data-target-ref="thread-1"/);
assert.match(moderatedBoardHtml, /data-target-kind="post" data-target-ref="post-201"/);
assert.match(moderatedBoardHtml, /<option value="spam">垃圾訊息<\/option>/);
assert.match(moderatedBoardHtml, /<option value="harassment">騷擾<\/option>/);
assert.match(moderatedBoardHtml, /<option value="illegal_content">違法內容<\/option>/);
assert.match(moderatedBoardHtml, /<option value="off_topic">離題<\/option>/);
assert.match(moderatedBoardHtml, /<option value="impersonation">冒充他人<\/option>/);
assert.match(moderatedBoardHtml, /<option value="other">其他<\/option>/);
assert.match(moderatedBoardHtml, /data-report-note/);
assert.match(moderatedBoardHtml, /選擇「其他」時，請留一段附註給板主。/);

// Anonymous sessions read tombstones and lock state but get no report action.
const anonymousModeratedHtml = renderPageBody(
  buildAppViewModel({
    route: { pageId: PAGE_IDS.board, params: { boardId: 'general' } },
    session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
    forum: {
      host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
      boards: [generalBoard],
      board: generalBoard,
      threads: moderatedThreads,
      capabilities: { canCreateThread: false, canReply: false },
    },
  }),
);
assert.match(anonymousModeratedHtml, /class="post-tombstone"/);
assert.match(anonymousModeratedHtml, /class="locked-banner"/);
assert.doesNotMatch(anonymousModeratedHtml, /data-action="submit-report"/);
assert.doesNotMatch(anonymousModeratedHtml, /class="thread-reply"/);

// Moderation console: queue grouped by board, action buttons, audit history.
const moderationConsoleVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.moderation, params: {} },
  session: moderatedSession,
  forum: {
    host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
    boards: [generalBoard],
    moderation: {
      status: 'moderator',
      reportGroups: groupReportsByBoard(
        CONTRACT_FIXTURES.moderation.openReports.map(normalizeReport),
      ),
      auditActions: CONTRACT_FIXTURES.moderation.auditActions.map(
        normalizeModerationAction,
      ),
      error: null,
    },
  },
});
const moderationConsoleHtml = renderPageBody(moderationConsoleVm);
assert.match(moderationConsoleHtml, /板務主控台/);
assert.match(moderationConsoleHtml, /待處理檢舉 · 3/);
assert.match(moderationConsoleHtml, /BOARD · #general/);
assert.match(moderationConsoleHtml, /BOARD · #verified-humans/);
assert.match(moderationConsoleHtml, /data-action="moderation-action"/);
assert.match(moderationConsoleHtml, /data-mod-action="dismiss_report"/);
assert.match(moderationConsoleHtml, /data-mod-action="remove_post_from_board"/);
assert.match(moderationConsoleHtml, /data-mod-action="lock_thread"/);
assert.match(moderationConsoleHtml, /data-mod-action="unlock_thread"/);
assert.match(moderationConsoleHtml, /駁回檢舉/);
assert.match(moderationConsoleHtml, /自看板移除/);
assert.match(moderationConsoleHtml, /鎖定討論串/);
assert.match(moderationConsoleHtml, /解鎖討論串/);
assert.match(moderationConsoleHtml, /data-report-id="41"/);
assert.match(moderationConsoleHtml, /冒充板主發言/);
assert.match(moderationConsoleHtml, /檢舉人/);
assert.match(moderationConsoleHtml, /處理紀錄/);
assert.match(moderationConsoleHtml, /post-101/);

// Relay 403: a renderable not-a-moderator state without queue or actions.
const forbiddenConsoleHtml = renderPageBody(
  buildAppViewModel({
    route: { pageId: PAGE_IDS.moderation, params: {} },
    session: moderatedSession,
    forum: {
      moderation: {
        status: 'not_moderator',
        reportGroups: [],
        auditActions: [],
        error: CONTRACT_FIXTURES.errors.notBoardModerator,
      },
    },
  }),
);
assert.match(forbiddenConsoleHtml, /403 · NOT BOARD MODERATOR/);
assert.match(forbiddenConsoleHtml, /需要板主權限/);
assert.doesNotMatch(forbiddenConsoleHtml, /data-action="moderation-action"/);
assert.doesNotMatch(forbiddenConsoleHtml, /待處理檢舉/);

// Signed-out console prompts for an app-approved session.
const signedOutConsoleHtml = renderPageBody(
  buildAppViewModel({
    route: { pageId: PAGE_IDS.moderation, params: {} },
    session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
    forum: {
      moderation: {
        status: 'signed_out',
        reportGroups: [],
        auditActions: [],
        error: null,
      },
    },
  }),
);
assert.match(signedOutConsoleHtml, /登入後管理板務/);
assert.match(signedOutConsoleHtml, /href="#\/login"/);
assert.doesNotMatch(signedOutConsoleHtml, /data-action="moderation-action"/);

// English locale renders the same moderation surfaces with English copy.
setCurrentLocale('en');
const englishConsoleHtml = renderPageBody(moderationConsoleVm);
assert.match(englishConsoleHtml, /Moderation console/);
assert.match(englishConsoleHtml, /Open reports · 3/);
assert.match(englishConsoleHtml, /Dismiss report/);
assert.match(englishConsoleHtml, /Remove from board/);
const englishBoardHtml = renderPageBody(moderatedBoardVm);
assert.match(englishBoardHtml, /Removed from this board · Spam/);
assert.match(englishBoardHtml, /Thread locked · Harassment/);
setCurrentLocale('zh-Hant');

console.log('ok - forum page renderers');
