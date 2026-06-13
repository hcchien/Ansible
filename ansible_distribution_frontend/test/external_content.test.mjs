import assert from 'node:assert/strict';

import {
  CONTRACT_FIXTURES,
  createFixtureAppViewClient,
  createFixtureForumHostClient,
} from '../src/contract_fixtures.mjs';
import {
  createForumDataAdapter,
  normalizeExternalItem,
  normalizeHostedBoard,
} from '../src/forum_data_adapter.mjs';
import { renderPageBody } from '../src/forum_page_renderers.mjs';
import { PAGE_IDS, buildAppViewModel } from '../src/state_model.mjs';
import { setCurrentLocale } from '../src/web_i18n.mjs';

setCurrentLocale('zh-Hant');

function externalAdapter({ hostOptions = {}, appViewOptions = {} } = {}) {
  return createForumDataAdapter({
    relayBaseUrl: 'http://localhost:4001',
    forumHostClient: createFixtureForumHostClient({
      includeExternalBoard: true,
      ...hostOptions,
    }),
    appViewClient: createFixtureAppViewClient(appViewOptions),
  });
}

// --- normalization ---------------------------------------------------------

assert.equal(
  normalizeHostedBoard(CONTRACT_FIXTURES.forum.externalBoard).postingPolicy.externalInclusion,
  true,
  'external_inclusion in posting_policy normalizes to externalInclusion=true',
);
assert.equal(
  normalizeHostedBoard(CONTRACT_FIXTURES.forum.boards[0]).postingPolicy.externalInclusion,
  false,
  'a board without external_inclusion defaults externalInclusion=false',
);

const normalizedItem = normalizeExternalItem(
  CONTRACT_FIXTURES.forum.externalResponse.items[0],
);
assert.equal(normalizedItem.external, true);
assert.equal(normalizedItem.reputationTier, 'external_unverified');
assert.equal(normalizedItem.complianceLevel, 'compatible');
assert.equal(normalizedItem.instance, 'g0v.social');
assert.equal(
  normalizeExternalItem({ compliance_level: 'totally-trusted' }).complianceLevel,
  'unknown',
  'unrecognized compliance levels coerce to unknown',
);

// --- data adapter: fetches external content only when opted in -------------

const optedInState = await externalAdapter().loadBoardPage({ boardId: 'fediverse-watch' });
assert.equal(optedInState.board.id, 'fediverse-watch');
assert.equal(optedInState.externalContent.unavailable, false);
assert.equal(optedInState.externalContent.items.length, 2);
assert.equal(optedInState.externalContent.items[0].external, true);

// A board without external_inclusion must NOT trigger an AppView fetch.
let appViewCalled = false;
const noFetchAdapter = createForumDataAdapter({
  relayBaseUrl: 'http://localhost:4001',
  forumHostClient: createFixtureForumHostClient({ includeExternalBoard: true }),
  appViewClient: {
    async fetchBoardExternalContent() {
      appViewCalled = true;
      return CONTRACT_FIXTURES.forum.externalResponse;
    },
  },
});
const nativeState = await noFetchAdapter.loadBoardPage({ boardId: 'general' });
assert.equal(nativeState.externalContent, null, 'non-opted-in board has no externalContent');
assert.equal(appViewCalled, false, 'non-opted-in board makes no AppView fetch');

// AppView outage degrades gracefully: board still loads, section marked unavailable.
const outageState = await externalAdapter({
  appViewOptions: { outcome: 'unavailable' },
}).loadBoardPage({ boardId: 'fediverse-watch' });
assert.equal(outageState.board.id, 'fediverse-watch', 'board page still loads on AppView outage');
assert.equal(outageState.error, null, 'AppView outage is not a board-page error');
assert.equal(outageState.externalContent.unavailable, true);
assert.deepEqual(outageState.externalContent.items, []);

// --- renderer: labeled, badged, escaped section ----------------------------

function externalVm(forumState, boardId = 'fediverse-watch') {
  return buildAppViewModel({
    route: { pageId: PAGE_IDS.board, params: { boardId } },
    session: { authenticated: false, trustTier: 'anonymous', scopes: [] },
    forum: { ...forumState, capabilities: { canCreateThread: false, canReply: false } },
  });
}

const optedInHtml = renderPageBody(externalVm(optedInState));
assert.match(optedInHtml, /data-external-section/, 'external section renders when board opted in');
assert.match(optedInHtml, /站外內容/, 'section is labeled (站外內容)');
assert.match(optedInHtml, /class="external-origin-badge"/, 'external origin badge renders');
assert.match(optedInHtml, /來自 g0v.social/, 'origin instance is shown');
assert.match(optedInHtml, /g0v.social\/users\/alice/, 'actor is shown');
assert.match(optedInHtml, /compliance-badge is-compatible/, 'compatible compliance badge renders');
assert.match(optedInHtml, /compliance-badge is-unknown/, 'unknown compliance badge renders');
assert.match(optedInHtml, /相容來源/);
assert.match(optedInHtml, /未評估來源/);
// Content is escaped — the script payload must not appear as a live tag.
assert.match(optedInHtml, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/, 'external content is HTML-escaped');
assert.doesNotMatch(optedInHtml, /<script>alert\(1\)<\/script>/, 'no raw script tag leaks through');

// A board WITHOUT external_inclusion renders no external section.
const nativeBoard = normalizeHostedBoard(CONTRACT_FIXTURES.forum.boards[0]);
const nativeHtml = renderPageBody(
  externalVm(
    {
      host: optedInState.host,
      boards: [nativeBoard],
      board: nativeBoard,
      threads: [],
      externalContent: null,
    },
    'general',
  ),
);
assert.doesNotMatch(nativeHtml, /data-external-section/, 'no external section for non-opted-in board');
assert.doesNotMatch(nativeHtml, /站外內容/, 'no 站外 label for non-opted-in board');

// AppView outage: section renders with an unavailable empty state, board intact.
const outageHtml = renderPageBody(externalVm(outageState));
assert.match(outageHtml, /data-external-section/, 'opted-in board still shows the section on outage');
assert.match(outageHtml, /站外內容目前無法載入/, 'outage shows the unavailable empty state');
assert.doesNotMatch(outageHtml, /class="external-item"/, 'no items render on outage');

// English parity check for the section copy.
setCurrentLocale('en');
const optedInHtmlEn = renderPageBody(externalVm(optedInState));
assert.match(optedInHtmlEn, /From the fediverse/);
assert.match(optedInHtmlEn, /Compatible source/);
assert.match(optedInHtmlEn, /Unknown source/);
setCurrentLocale('zh-Hant');

console.log('ok - external content surfacing (board opt-in, badges, escaping, graceful degradation)');
