import { ERROR_TYPES } from './error_taxonomy.mjs';

// Frontend mirror of the relay reason-code enum
// (ansible_relay forum_host/report_reason.ex). The relay stays authoritative;
// this mirror only makes the picker and local validation possible.
export const REPORT_REASON_CODES = Object.freeze([
  'spam',
  'harassment',
  'illegal_content',
  'off_topic',
  'impersonation',
  'other',
]);

export const MODERATION_ACTIONS = Object.freeze([
  'dismiss_report',
  'remove_post_from_board',
  'lock_thread',
  'unlock_thread',
  'hide_context_note',
]);

export const REPORT_TARGET_KINDS = Object.freeze(['thread', 'post', 'context_note']);

export function isValidReasonCode(code) {
  return REPORT_REASON_CODES.includes(code);
}

export function reasonRequiresNote(code) {
  return code === 'other';
}

// Returns a semantic frontend error (error_taxonomy shape) or null when the
// draft is acceptable. Mirrors the relay rule: `other` needs a non-empty note.
export function validateReportDraft({ reasonCode, note } = {}) {
  if (!isValidReasonCode(reasonCode)) {
    return invalidReportError('invalid_reason_code');
  }

  if (reasonRequiresNote(reasonCode) && !String(note ?? '').trim()) {
    return invalidReportError('note_required');
  }

  return null;
}

function invalidReportError(code) {
  return {
    type: ERROR_TYPES.invalidRequest,
    message: code,
    retryable: false,
    code,
    detail: undefined,
  };
}

export function normalizeReport(report) {
  return {
    id: report?.id ?? null,
    targetKind: report?.target_kind ?? '',
    targetRef: report?.target_ref ?? '',
    boardId: report?.board_id ?? '',
    reporterDid: report?.reporter_did ?? null,
    reasonCode: report?.reason_code ?? null,
    note: report?.note ?? null,
    status: report?.status ?? 'open',
    insertedAt: report?.inserted_at ?? null,
  };
}

export function normalizeModerationAction(action) {
  return {
    id: action?.id ?? null,
    action: action?.action ?? '',
    targetRef: action?.target_ref ?? '',
    boardId: action?.board_id ?? '',
    moderatorDid: action?.moderator_did ?? null,
    reasonCode: action?.reason_code ?? null,
    reportId: action?.report_id ?? null,
    insertedAt: action?.inserted_at ?? null,
  };
}

export function normalizeModerationState(state) {
  return {
    removedPosts: (state?.removed_posts ?? []).map((entry) => ({
      targetRef: entry?.target_ref ?? '',
      reasonCode: entry?.reason_code ?? null,
    })),
    lockedThreads: (state?.locked_threads ?? []).map((entry) => ({
      threadId: entry?.thread_id ?? '',
      reasonCode: entry?.reason_code ?? null,
    })),
    hiddenContextNotes: (state?.hidden_context_notes ?? []).map((entry) => ({
      noteId: entry?.note_id ?? '',
      reasonCode: entry?.reason_code ?? null,
    })),
  };
}

// Groups already-normalized reports for the console queue, preserving the
// relay's report ordering within each board group.
export function groupReportsByBoard(reports = []) {
  const groups = new Map();

  for (const report of reports) {
    const boardId = report.boardId || 'unknown';
    if (!groups.has(boardId)) {
      groups.set(boardId, { boardId, reports: [] });
    }
    groups.get(boardId).reports.push(report);
  }

  return Array.from(groups.values());
}

// Console action set per target kind: posts can be removed from the board,
// threads can be locked/unlocked. Dismiss is always available.
export function actionsForTargetKind(targetKind) {
  if (targetKind === 'post') {
    return ['dismiss_report', 'remove_post_from_board'];
  }

  if (targetKind === 'context_note') {
    return ['dismiss_report', 'hide_context_note'];
  }

  return ['dismiss_report', 'lock_thread', 'unlock_thread'];
}

// Overlays the public board moderation-state onto normalized threads so
// listings render locked banners / removed-post tombstones even when the
// thread payload itself was not yet annotated by the relay.
export function applyModerationStateToThreads(threads = [], moderationState) {
  const state = moderationState ?? { removedPosts: [], lockedThreads: [] };
  const lockedById = new Map(
    state.lockedThreads.map((entry) => [entry.threadId, entry.reasonCode]),
  );
  const removedByRef = new Map(
    state.removedPosts.map((entry) => [entry.targetRef, entry.reasonCode]),
  );

  return threads.map((thread) => {
    const lockReason = lockedById.get(thread.id);
    const posts = (thread.posts ?? []).map((post) => {
      if (post.removed) return post;
      if (!removedByRef.has(post.id)) return post;

      return {
        ...post,
        removed: true,
        body: null,
        reasonCode: removedByRef.get(post.id),
      };
    });

    if (lockReason === undefined) {
      return { ...thread, posts };
    }

    return {
      ...thread,
      posts,
      locked: true,
      lockReasonCode: thread.lockReasonCode ?? lockReason,
    };
  });
}
