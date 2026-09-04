import assert from 'node:assert/strict';

import { CONTRACT_FIXTURES } from '../src/contract_fixtures.mjs';
import {
  normalizeForumHost,
  normalizeHostedBoard,
} from '../src/forum_data_adapter.mjs';
import { renderCommunityNotes, renderPageBody } from '../src/forum_page_renderers.mjs';
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

const faqHtml = renderPageBody(buildAppViewModel({
  route: { pageId: PAGE_IDS.faq, params: {} },
  session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
}));

const communityNotesHtml = renderCommunityNotes([
  {
    note_id: 'cn-1',
    author_did: 'did:key:bob',
    body: '<script>not executable</script> Additional context',
    sources: [
      { url: 'https://example.test/source?q=<unsafe>', title: 'Trusted <source>' },
      { url: 'javascript:alert(1)', title: 'Unsafe source' },
    ],
    aggregate: {
      status: 'helpful',
      rating_count: 5,
      scorer_id: 'elix_host_consensus',
      scorer_version: 1,
      top_tags: [{ tag: 'good_sources', count: 4 }],
    },
  },
], { authenticated: true, session: { subject: 'did:key:alice' } });
assert.match(communityNotesHtml, /<details class="community-notes"/);
assert.doesNotMatch(communityNotesHtml, /<details class="community-notes"[^>]*\sopen(?:\s|>)/);
assert.match(communityNotesHtml, /<summary class="community-notes-summary">/);
assert.match(communityNotesHtml, /1 則獲評有幫助/);
assert.match(communityNotesHtml, /社群評價為有幫助/);
assert.match(communityNotesHtml, /elix_host_consensus v1/);
assert.match(communityNotesHtml, /good_sources/);
assert.match(communityNotesHtml, /請使用持有 DID 的 Elix app 簽署評分/);
assert.doesNotMatch(communityNotesHtml, /data-action="rate-context-note"/);
assert.match(communityNotesHtml, /rel="noopener noreferrer"/);
assert.match(communityNotesHtml, /&lt;script&gt;not executable&lt;\/script&gt;/);
assert.doesNotMatch(communityNotesHtml, /javascript:alert|Unsafe source|rater_did/);
assert.match(faqHtml, /Elix 是什麼？/);
assert.match(faqHtml, /我一定要做真人驗證嗎？/);
assert.match(faqHtml, /為什麼需要同步？/);
assert.match(faqHtml, /我的資料保存在哪裡？/);
assert.match(faqHtml, /我看到發文者是 did:…，這是 bug 嗎？/);
assert.match(faqHtml, /背景身分編號/);
assert.match(faqHtml, /貼文旁的簽章圖示是什麼？/);
assert.match(faqHtml, /沒有簽章圖示通常表示來源沒有提供可驗證的作者證明/);
assert.match(faqHtml, /href="#\/boards"/);
assert.doesNotMatch(faqHtml, /<summary>Relay、Forum Host、AppView 是什麼？<\/summary>/);
assert.match(faqHtml, /想知道背後怎麼運作？/);
assert.match(faqHtml, /class="faq-nerds"/);
assert.match(faqHtml, /可以用 AI 協助我整理社群資料嗎？/);
assert.match(faqHtml, /本地 MCP 存取預設為唯讀/);
assert.match(faqHtml, /真人驗證怎麼兼顧隱私？/);
assert.match(faqHtml, /零知識證明/);
assert.match(faqHtml, /ZKPassport 證明/);
assert.match(faqHtml, /數位皮夾怎麼避免揭露太多資料？/);
assert.match(faqHtml, /憑證只有年齡、國籍和真人驗證嗎？我或組織也能發嗎？/);
assert.match(faqHtml, /Elix 愛好者/);

const profileHtml = renderPageBody(buildAppViewModel({
  route: { pageId: PAGE_IDS.profile, params: { did: 'did:elix:mira' } },
  session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
  forum: {
    profile: {
      did: 'did:elix:mira',
      displayName: 'Mira Lin',
      handle: 'mira.elix.cool',
      bio: '寫字，也聽別人說話。',
      reputationTier: 'verified_human',
      missing: false,
    },
    profilePosts: [
      {
        id: 'post-1',
        type: 'discussion',
        title: '一則公開討論',
        body: '只顯示公開內容。',
        boardId: 'general',
        threadId: 'thread-1',
        createdAt: '2026-08-27T04:00:00Z',
      },
    ],
  },
}));
assert.match(profileHtml, /class="cols profile-layout"/);
assert.match(profileHtml, /Mira Lin/);
assert.match(profileHtml, /@mira\.elix\.cool/);
assert.match(profileHtml, /寫字，也聽別人說話。/);
assert.match(profileHtml, /已驗證真人/);
assert.match(profileHtml, /只顯示對方主動發布/);
assert.match(profileHtml, /#\/boards\/general\/threads\/thread-1/);
assert.doesNotMatch(profileHtml, /國籍|18\+|passport|legal name/i);

const homeHarness = createFrontendFlowHarness({ routeHash: '#/', sessionMode: 'anonymous' });
const homeState = await runPublicHomeFlow(homeHarness);
const homeHtml = renderPageBody(homeState.viewModel);
assert.match(homeHtml, /Local Forum Host/);
assert.match(homeHtml, /General/);
// The handoff's feed column opens straight into the composer and the stream:
// no page heading, kicker or blurb. The read-only state is carried by the
// header's session pill instead — asserted in forum_shell_renderer.test.mjs.
assert.doesNotMatch(homeHtml, /class="feed-head"/);
assert.doesNotMatch(homeHtml, /Elix 是重視身分的社群 App/);
// The heading survives for assistive tech, just not on screen.
assert.match(homeHtml, /<h1 id="feed-title" class="visually-hidden">/);
assert.match(homeHtml, /RELAY · BOARD · #general/);
assert.match(homeHtml, /打開看板/);
assert.match(homeHtml, /Note/);
assert.match(homeHtml, /登入後可簽署發文/);
assert.match(homeHtml, /class="cols social-home mobile-focus-home"/);
assert.match(homeHtml, /class="mobile-focus-stage"/);
assert.match(homeHtml, /data-scene="personal"/);
// The revised handoff drops the tab row above the feed: the home page is one
// chronological stream, and each post carries its own source label instead.
assert.doesNotMatch(homeHtml, /scene-switcher|select-scene|scene-help|swipe-coachmark|scene-track/);
assert.doesNotMatch(homeHtml, /往左滑/);
// Compose lives in the tab bar's centre key on mobile, so there is no
// separate floating action button to collide with it.
assert.doesNotMatch(homeHtml, /class="mobile-compose-fab"/);
assert.match(homeHtml, /已訂閱看板/);
assert.doesNotMatch(homeHtml, /Mira Lin|FROM A FOLLOW|關於信任的地形|MURMUR · 0:38|AI · 橫向橋/);
assert.doesNotMatch(homeHtml, /工作階段/);
assert.doesNotMatch(homeHtml, /RELAY · 來源/);
assert.doesNotMatch(homeHtml, /Relay 資料/);
assert.doesNotMatch(homeHtml, /傳給圈內/);
assert.doesNotMatch(homeHtml, /App-approved web session login|Read only|Open board|Login required for signed posting/);

const undescribedBoardHomeHtml = renderPageBody({
  page: { id: PAGE_IDS.home },
  boards: [
    {
      id: 'fifa2026',
      slug: 'fifa2026',
      title: 'FIFA2026',
      description: '',
      permissions: { canWrite: true },
    },
  ],
  host: { displayName: 'Local Forum Host' },
  session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
});
assert.match(undescribedBoardHomeHtml, /FIFA2026/);
assert.doesNotMatch(undescribedBoardHomeHtml, /Relay server 回傳的 hosted board/);
assert.doesNotMatch(undescribedBoardHomeHtml, /Relay server returned this hosted board/);

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

const deliberationHtml = renderPageBody(buildAppViewModel({
  route: {
    pageId: PAGE_IDS.deliberation,
    params: { boardId: 'general', deliberationId: 'd-1' },
  },
  session: {
    authenticated: true,
    trustTier: 'self_custody_did',
    capabilities: { canPost: true, canReply: true },
  },
  forum: {
    board: { id: 'general', title: 'General' },
    deliberation: {
      id: 'd-1',
      title: '每週發布？',
      prompt: '速度與穩定性要如何平衡？',
      exportMode: 'aggregates_only',
      viewerResponses: { 's-1': { stance: 'agree', last_intent_id: 'v-1' } },
      statements: [{ id: 's-1', text: '每週發布一個小版本。' }],
      report: {
        participant_count: 5,
        response_count: 5,
        cluster_status: 'aggregate_only',
        consensus: [{ text: '每週發布一個小版本。', agree_ratio: 0.8 }],
      },
    },
    capabilities: { canCreateThread: true, canReply: true },
  },
}));
assert.match(deliberationHtml, /每週發布？/);
assert.match(deliberationHtml, /共識與歧異/);
assert.match(deliberationHtml, /btn small is-selected/);
assert.match(deliberationHtml, /class="opinion-voting-stage"/);
assert.match(deliberationHtml, /class="opinion-statement-card"/);
assert.match(deliberationHtml, /class="opinion-map-placeholder"/);
assert.match(deliberationHtml, /意見地圖/);
assert.match(deliberationHtml, /只會匯出整體統計/);
assert.doesNotMatch(deliberationHtml, /did:/);

const gatedBoard = normalizeHostedBoard(CONTRACT_FIXTURES.forum.gatedBoard);
const gatedForum = {
  host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
  boards: [gatedBoard],
  board: gatedBoard,
  threads: [],
  deliberations: [{
    id: 'deliberation-1',
    title: '怎麼產生第二個有本土意識的政黨',
    prompt: '比較不同路徑與代價。',
    statementCount: 2,
    participantCount: 0,
  }],
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
assert.match(belowTierHtml, /class="card deliberation-list is-populated"/);
assert.match(belowTierHtml, /怎麼產生第二個有本土意識的政黨/);
assert.match(belowTierHtml, /真人驗證版/);
assert.match(belowTierHtml, /這個板需要「已驗證真人」層級才能發文/);
assert.match(belowTierHtml, /class="gate-blocked"/);
assert.match(belowTierHtml, /<button class="primary-action" type="button" disabled>/);
assert.match(belowTierHtml, /你目前的層級是「自持有 DID」/);
assert.match(belowTierHtml, /請在 Elix app 完成真人驗證/);
assert.doesNotMatch(belowTierHtml, /data-action="new-thread"/);
assert.doesNotMatch(belowTierHtml, /data-action="new-deliberation"/);

const gatedDeliberationHtml = renderPageBody(buildAppViewModel({
  route: {
    pageId: PAGE_IDS.deliberation,
    params: { boardId: 'verified-humans', deliberationId: 'd-gated' },
  },
  session: belowTierVm.session,
  forum: {
    ...gatedForum,
    deliberation: {
      id: 'd-gated',
      title: '需驗證的審議',
      prompt: '只有符合本板發言條件者可以參與。',
      exportMode: 'aggregates_only',
      statements: [{ id: 's-gated', text: '這是一句測試陳述。' }],
      report: { cluster_status: 'aggregate_only' },
    },
  },
}));
assert.match(gatedDeliberationHtml, /只有符合本板發言條件者可以參與/);
assert.match(gatedDeliberationHtml, /<button class="btn" type="button" disabled>/);
assert.match(gatedDeliberationHtml, /請在 Elix app 完成真人驗證/);
assert.doesNotMatch(gatedDeliberationHtml, /data-action="add-deliberation-statement"/);
assert.doesNotMatch(gatedDeliberationHtml, /data-action="cast-deliberation-vote"/);

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

const credentialBoard = normalizeHostedBoard({
  hosted_board_id: 'members',
  slug: 'members',
  title: 'Members',
  permissions: { read: true, write: true },
  access_policy: {
    version: 1,
    discovery: 'public',
    read: { requirement: 'public' },
    post: { requirement: 'member' },
    moderate: { requirement: 'board_moderator' },
    requirements: {
      member: {
        credential_type: 'MembershipCredential',
        trusted_issuers: ['did:web:issuer.example'],
        claims: [{ path: 'membership', op: 'equals', value: 'member' }],
        holder_binding: 'required',
        status: { required: true },
      },
    },
    capability_ttl_seconds: 300,
    content_visibility: 'public',
    federation: 'enabled',
  },
});
const credentialBoardVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.board, params: { boardId: 'members' } },
  session: {
    authenticated: true,
    trustTier: 'verified_human',
    subjectDid: 'did:elix:fixture',
    scopes: ['forum:read', 'forum:post'],
    capabilities: { canPost: true, canReply: true },
  },
  forum: {
    host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
    boards: [credentialBoard],
    board: credentialBoard,
    threads: [],
    capabilities: { canCreateThread: true, canReply: true },
  },
});
const credentialBoardHtml = renderPageBody(credentialBoardVm);
assert.match(credentialBoardHtml, /需憑證/);
assert.match(credentialBoardHtml, /MembershipCredential/);
assert.match(credentialBoardHtml, /membership = member/);
assert.match(credentialBoardHtml, /憑證內容不會進入瀏覽器/);
assert.match(credentialBoardHtml, /<button class="primary-action" type="button" disabled>/);
assert.doesNotMatch(credentialBoardHtml, /data-action="new-thread"/);

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
assert.match(sessionsHtml, /class="language-picker"/);
for (const locale of ['en', 'zh-Hant', 'fr', 'es', 'ja', 'ko', 'de', 'it']) {
  assert.match(sessionsHtml, new RegExp(`href="\\?lang=${locale}#\\/sessions"`));
}
for (const nativeName of ['English', '繁體中文', 'Français', 'Español', '日本語', '한국어', 'Deutsch', 'Italiano']) {
  assert.match(sessionsHtml, new RegExp(nativeName));
}
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
assert.match(englishHomeHtml, /Boards/);
assert.match(englishHomeHtml, /Open board/);
assert.doesNotMatch(englishHomeHtml, /Swipe left/);
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

// Board rows expose real thread detail links instead of inert list text.
assert.match(moderatedBoardHtml, /href="#\/boards\/general\/threads\/thread-9"/);
assert.match(moderatedBoardHtml, /href="#\/boards\/general\/threads\/thread-1"/);
assert.match(moderatedBoardHtml, /class="board-thread-row is-signed"/);
assert.match(moderatedBoardHtml, /class="board-thread-status"/);
assert.match(moderatedBoardHtml, /class="board-thread-board"/);
assert.match(moderatedBoardHtml, /#<\/span>General/);
assert.match(moderatedBoardHtml, /class="board-thread-avatar"/);
assert.match(moderatedBoardHtml, /class="did-handle profile-author-link"/);
assert.match(moderatedBoardHtml, /class="pk-pill"/);
assert.doesNotMatch(moderatedBoardHtml, /class="thread-posts"/);

// Board rows stay summary-only; removed content is visible in the thread detail projection.
assert.doesNotMatch(moderatedBoardHtml, /removed body text/);
assert.doesNotMatch(moderatedBoardHtml, /kept body text/);

// Locked-thread banner with reason; reply affordance disappears on lock.
assert.match(moderatedBoardHtml, /class="locked-banner"/);
assert.match(moderatedBoardHtml, /討論串已鎖定 · 騷擾/);
assert.match(moderatedBoardHtml, /class="locked-badge"/);
assert.doesNotMatch(moderatedBoardHtml, /鎖定中的討論串不接受新回覆/);
assert.doesNotMatch(moderatedBoardHtml, /class="thread-reply"/);
const lockedItemHtml = moderatedBoardHtml.slice(
  moderatedBoardHtml.indexOf('Reported thread'),
  moderatedBoardHtml.indexOf('Open thread'),
);
assert.doesNotMatch(lockedItemHtml, /class="thread-reply"/);

// Signed-in thread report picker: reason enum + note field + required-note hint.
assert.match(moderatedBoardHtml, /data-action="submit-report"/);
assert.match(moderatedBoardHtml, /data-target-kind="thread" data-target-ref="thread-1"/);
assert.doesNotMatch(moderatedBoardHtml, /data-target-kind="post" data-target-ref="post-201"/);
assert.match(moderatedBoardHtml, /<option value="spam">垃圾訊息<\/option>/);
assert.match(moderatedBoardHtml, /<option value="harassment">騷擾<\/option>/);
assert.match(moderatedBoardHtml, /<option value="illegal_content">違法內容<\/option>/);
assert.match(moderatedBoardHtml, /<option value="off_topic">離題<\/option>/);
assert.match(moderatedBoardHtml, /<option value="impersonation">冒充他人<\/option>/);
assert.match(moderatedBoardHtml, /<option value="other">其他<\/option>/);
assert.match(moderatedBoardHtml, /data-report-note/);
assert.match(moderatedBoardHtml, /選擇「其他」時，請留一段附註給板主。/);

// Anonymous sessions read thread lock state on the board list but get no report action.
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
assert.doesNotMatch(anonymousModeratedHtml, /class="post-tombstone"/);
assert.match(anonymousModeratedHtml, /class="locked-banner"/);
assert.doesNotMatch(anonymousModeratedHtml, /data-action="submit-report"/);
assert.doesNotMatch(anonymousModeratedHtml, /class="thread-reply"/);

const threadDetailVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.thread, params: { boardId: 'general', threadId: 'thread-1' } },
  session: moderatedSession,
  forum: {
    host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
    boards: [generalBoard],
    board: generalBoard,
    thread: {
      ...moderatedThreads[1],
      posts: [{ id: 'post-201', content: 'reply content from AppView' }],
    },
    threads: moderatedThreads,
    capabilities: { canCreateThread: true, canReply: true },
  },
});
const threadDetailHtml = renderPageBody(threadDetailVm);
assert.match(threadDetailHtml, /class="feed thread-detail"/);
assert.match(threadDetailHtml, /class="thread-detail-shell"/);
assert.match(threadDetailHtml, /class="thread-hd"/);
assert.match(threadDetailHtml, /THREAD · 討論串/);
assert.match(threadDetailHtml, /Open thread/);
assert.match(threadDetailHtml, /class="did-handle profile-author-link"/);
assert.match(threadDetailHtml, /class="pk-pill"/);
assert.match(threadDetailHtml, /class="thread-op"/);
assert.match(threadDetailHtml, /起頭 · <span class="thread-source-strong">signed · PK<\/span>/);
assert.match(threadDetailHtml, /reply content from AppView/);
assert.match(threadDetailHtml, /class="thread-replies"/);
assert.match(threadDetailHtml, /class="thread-reply-item"/);
assert.match(threadDetailHtml, /class="thread-reply-avatar/);
assert.match(threadDetailHtml, /class="thread-mini-actions"/);
assert.match(threadDetailHtml, /class="thread-reply-composer"/);
assert.match(threadDetailHtml, /data-action="open-reply-draft"/);
assert.match(threadDetailHtml, /class="right-rail thread-context-rail"/);
assert.match(threadDetailHtml, /看板 · BOARD/);
assert.match(threadDetailHtml, /#General/);
assert.match(threadDetailHtml, /href="#\/boards\/general"/);
assert.match(threadDetailHtml, /data-target-kind="thread" data-target-ref="thread-1"/);
assert.match(threadDetailHtml, /data-target-kind="post" data-target-ref="post-201"/);
assert.doesNotMatch(threadDetailHtml, /class="thread-posts"/);
assert.doesNotMatch(threadDetailHtml, /路徑不可用/);

const replyDraftHtml = renderPageBody(threadDetailVm, {
  replyDraft: {
    boardId: 'general',
    threadId: 'thread-1',
    body: 'Hello @Alice',
    mentionPickerOpen: true,
    mentionQuery: 'ali',
    mentionResults: [{
      did: 'did:elix:alice',
      handle: 'alice.elix.cool',
      displayName: 'Alice',
    }],
  },
});
assert.match(replyDraftHtml, /data-reply-form/);
assert.match(replyDraftHtml, /data-reply-body/);
assert.match(replyDraftHtml, /Hello @Alice/);
assert.match(replyDraftHtml, /data-reply-mention-search/);
assert.match(replyDraftHtml, /data-action="select-reply-mention"/);
assert.match(replyDraftHtml, /data-did="did:elix:alice"/);
assert.match(replyDraftHtml, /只有明確選取的公開人物會收到通知/);

const handledThreadDetailVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.thread, params: { boardId: 'general', threadId: 'thread-handled' } },
  session: moderatedSession,
  forum: {
    host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
    boards: [generalBoard],
    board: generalBoard,
    thread: {
      id: 'thread-handled',
      title: 'Handle thread',
      authorDid: 'did:plc:threadauthorabcdef',
      authorDisplayName: 'Thread Author',
      authorHandle: 'thread-author.elix.cool',
      posts: [
        {
          id: 'post-handled',
          content: 'reply with handle',
          authorDid: 'did:plc:replyauthorabcdef',
          authorDisplayName: 'Reply Author',
          authorHandle: 'reply-author.elix.cool',
        },
      ],
    },
    threads: [],
    capabilities: { canCreateThread: true, canReply: true },
  },
});
const handledThreadDetailHtml = renderPageBody(handledThreadDetailVm);
assert.match(handledThreadDetailHtml, /Thread Author/);
assert.match(handledThreadDetailHtml, /Reply Author/);
assert.match(handledThreadDetailHtml, /Thread Author · @thread-author\.elix\.cool/);
assert.match(handledThreadDetailHtml, /Reply Author · @reply-author\.elix\.cool/);
assert.doesNotMatch(handledThreadDetailHtml, /did:plc\.\.\.abcdef/);

const anonymousHandledThreadDetailHtml = renderPageBody({
  ...handledThreadDetailVm,
  session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
});
assert.match(anonymousHandledThreadDetailHtml, /Reply Author/);
assert.doesNotMatch(anonymousHandledThreadDetailHtml, />匿名<\/span>/);

const lockedThreadDetailVm = buildAppViewModel({
  route: { pageId: PAGE_IDS.thread, params: { boardId: 'general', threadId: 'thread-9' } },
  session: moderatedSession,
  forum: {
    host: normalizeForumHost(CONTRACT_FIXTURES.forum.host),
    boards: [generalBoard],
    board: generalBoard,
    thread: moderatedThreads[0],
    threads: moderatedThreads,
    capabilities: { canCreateThread: true, canReply: false },
  },
});
const lockedThreadDetailHtml = renderPageBody(lockedThreadDetailVm);
assert.match(lockedThreadDetailHtml, /class="post-tombstone"/);
assert.match(lockedThreadDetailHtml, /已自此看板移除 · 垃圾訊息/);
assert.match(lockedThreadDetailHtml, /kept body text/);
assert.match(lockedThreadDetailHtml, /class="locked-banner"/);
assert.match(lockedThreadDetailHtml, /討論串已鎖定 · 騷擾/);
assert.match(lockedThreadDetailHtml, /鎖定中的討論串不接受新回覆/);

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
assert.match(englishBoardHtml, /Thread locked · Harassment/);
const englishLockedThreadDetailHtml = renderPageBody(lockedThreadDetailVm);
assert.match(englishLockedThreadDetailHtml, /Removed from this board · Spam/);
assert.match(englishLockedThreadDetailHtml, /Thread locked · Harassment/);
setCurrentLocale('zh-Hant');

const notificationsHtml = renderPageBody(
  buildAppViewModel({
    route: { pageId: PAGE_IDS.notifications, params: {} },
    session: moderatedSession,
    forum: {
      boards: [{ id: 'general', title: 'General' }],
      notifications: {
        unreadCount: 1,
        items: [
          {
            id: 'reply:post-2',
            type: 'reply_to_thread',
            actorDid: 'did:elix:alice',
            actorHandle: 'alice.elix.cool',
            boardId: 'general',
            threadId: 'thread-1',
            createdAt: '2026-08-22T01:02:00Z',
            isRead: false,
          },
        ],
      },
    },
  }),
);
assert.match(notificationsHtml, /回覆了你的討論串/);
assert.match(notificationsHtml, /data-action="open-notification"/);
assert.match(notificationsHtml, /data-action="mark-all-notifications-read"/);
assert.match(notificationsHtml, /notification-unread-dot/);
assert.match(notificationsHtml, /只保存在這個瀏覽器/);

const mentionNotificationsHtml = renderPageBody(
  buildAppViewModel({
    route: { pageId: PAGE_IDS.notifications, params: {} },
    session: moderatedSession,
    forum: {
      boards: [{ id: 'general', title: 'General' }],
      notifications: {
        unreadCount: 1,
        items: [{
          id: 'mention:post-3',
          type: 'mention',
          actorDid: 'did:elix:alice',
          boardId: 'general',
          threadId: 'thread-1',
          isRead: false,
        }],
      },
    },
  }),
);
assert.match(mentionNotificationsHtml, /在回覆中提及了你/);

console.log('ok - forum page renderers');
