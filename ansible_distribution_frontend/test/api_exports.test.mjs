import assert from 'node:assert/strict';

import {
  createHostedWebThread,
  createForumDataAdapter,
  createPageController,
  createRelayApiClient,
  createSessionLifecycle,
  createWebSessionChallenge,
  ERROR_TYPES,
  fetchBoardModerationState,
  fetchForumHostInfo,
  fetchHostedBoards,
  fetchWebModerationReports,
  listWebSessions,
  mentionToken,
  normalizeFrontendError,
  PAGE_IDS,
  parseRoute,
  REPORT_REASON_CODES,
  revokeWebSession,
  submitWebReport,
  validateReportDraft,
} from '../src/api.mjs';

assert.equal(typeof createRelayApiClient, 'function');
assert.equal(typeof createWebSessionChallenge, 'function');
assert.equal(typeof listWebSessions, 'function');
assert.equal(typeof revokeWebSession, 'function');
assert.equal(typeof fetchForumHostInfo, 'function');
assert.equal(typeof fetchHostedBoards, 'function');
assert.equal(typeof createHostedWebThread, 'function');
assert.equal(typeof createSessionLifecycle, 'function');
assert.equal(typeof createForumDataAdapter, 'function');
assert.equal(typeof normalizeFrontendError, 'function');
assert.equal(typeof createPageController, 'function');
assert.equal(typeof parseRoute, 'function');
assert.equal(typeof mentionToken, 'function');
assert.equal(typeof submitWebReport, 'function');
assert.equal(typeof fetchWebModerationReports, 'function');
assert.equal(typeof fetchBoardModerationState, 'function');
assert.equal(typeof validateReportDraft, 'function');
assert.equal(REPORT_REASON_CODES.length, 6);
assert.equal(ERROR_TYPES.missingScope, 'missing_scope');
assert.equal(ERROR_TYPES.notBoardModerator, 'not_board_moderator');
assert.equal(PAGE_IDS.board, 'board');
assert.equal(PAGE_IDS.moderation, 'moderation');

console.log('ok - api barrel exports frontend relay clients');
