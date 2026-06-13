import assert from 'node:assert/strict';

import { CONTRACT_FIXTURES } from '../src/contract_fixtures.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';
import {
  MODERATION_ACTIONS,
  REPORT_REASON_CODES,
  REPORT_TARGET_KINDS,
  actionsForTargetKind,
  applyModerationStateToThreads,
  groupReportsByBoard,
  isValidReasonCode,
  normalizeModerationAction,
  normalizeModerationState,
  normalizeReport,
  reasonRequiresNote,
  validateReportDraft,
} from '../src/moderation_model.mjs';

const tests = [];

function test(name, body) {
  tests.push({ name, body });
}

test('mirrors the relay reason-code and action enums', () => {
  assert.deepEqual(REPORT_REASON_CODES, [
    'spam',
    'harassment',
    'illegal_content',
    'off_topic',
    'impersonation',
    'other',
  ]);
  assert.deepEqual(MODERATION_ACTIONS, [
    'dismiss_report',
    'remove_post_from_board',
    'lock_thread',
    'unlock_thread',
  ]);
  assert.deepEqual(REPORT_TARGET_KINDS, ['thread', 'post']);
  assert.equal(isValidReasonCode('spam'), true);
  assert.equal(isValidReasonCode('not_a_reason'), false);
});

test('accepts drafts with a valid reason and requires a note only for other', () => {
  assert.equal(validateReportDraft({ reasonCode: 'spam' }), null);
  assert.equal(
    validateReportDraft({ reasonCode: 'other', note: '冒充板主發言' }),
    null,
  );
  assert.equal(reasonRequiresNote('other'), true);
  assert.equal(reasonRequiresNote('spam'), false);
});

test('rejects unknown reason codes with a semantic invalid-request error', () => {
  const error = validateReportDraft({ reasonCode: 'not_a_reason' });
  assert.equal(error.type, ERROR_TYPES.invalidRequest);
  assert.equal(error.code, 'invalid_reason_code');
});

test('rejects an "other" report without a note', () => {
  for (const note of [undefined, null, '', '   ']) {
    const error = validateReportDraft({ reasonCode: 'other', note });
    assert.equal(error.type, ERROR_TYPES.invalidRequest);
    assert.equal(error.code, 'note_required');
  }
});

test('normalizes relay reports, actions, and moderation state', () => {
  assert.deepEqual(normalizeReport(CONTRACT_FIXTURES.moderation.report), {
    id: 41,
    targetKind: 'post',
    targetRef: 'post-201',
    boardId: 'general',
    reporterDid: 'did:plc:reporter',
    reasonCode: 'spam',
    note: null,
    status: 'open',
    insertedAt: '2026-06-13T01:00:00Z',
  });
  assert.deepEqual(
    normalizeModerationAction(CONTRACT_FIXTURES.moderation.auditActions[0]),
    {
      id: 7,
      action: 'remove_post_from_board',
      targetRef: 'post-101',
      boardId: 'general',
      moderatorDid: 'did:plc:fixture',
      reasonCode: 'spam',
      reportId: 40,
      insertedAt: '2026-06-12T09:00:00Z',
    },
  );
  assert.deepEqual(
    normalizeModerationState(CONTRACT_FIXTURES.moderation.boardState),
    {
      removedPosts: [{ targetRef: 'post-101', reasonCode: 'spam' }],
      lockedThreads: [{ threadId: 'thread-9', reasonCode: 'harassment' }],
    },
  );
});

test('groups open reports by board preserving relay ordering', () => {
  const groups = groupReportsByBoard(
    CONTRACT_FIXTURES.moderation.openReports.map(normalizeReport),
  );

  assert.deepEqual(
    groups.map((group) => [group.boardId, group.reports.map((r) => r.id)]),
    [
      ['general', [41, 42]],
      ['verified-humans', [43]],
    ],
  );
});

test('offers post actions for posts and lock actions for threads', () => {
  assert.deepEqual(actionsForTargetKind('post'), [
    'dismiss_report',
    'remove_post_from_board',
  ]);
  assert.deepEqual(actionsForTargetKind('thread'), [
    'dismiss_report',
    'lock_thread',
    'unlock_thread',
  ]);
});

test('overlays tombstones and lock state onto board threads', () => {
  const threads = applyModerationStateToThreads(
    [
      {
        id: 'thread-9',
        title: 'Locked thread',
        posts: [
          { id: 'post-101', body: 'removed body' },
          { id: 'post-102', body: 'kept body' },
        ],
      },
      { id: 'thread-1', title: 'Untouched', posts: [] },
    ],
    normalizeModerationState(CONTRACT_FIXTURES.moderation.boardState),
  );

  assert.equal(threads[0].locked, true);
  assert.equal(threads[0].lockReasonCode, 'harassment');
  assert.deepEqual(threads[0].posts[0], {
    id: 'post-101',
    removed: true,
    body: null,
    reasonCode: 'spam',
  });
  assert.equal(threads[0].posts[1].body, 'kept body');
  assert.equal(threads[1].locked, undefined);
});

for (const { name, body } of tests) {
  await body();
  console.log(`ok - ${name}`);
}
