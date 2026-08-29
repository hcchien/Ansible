import { createRelayApiClient } from './relay_api_client.mjs';

export async function fetchForumHostInfo(options) {
  return relayClient(options).getJson('/api/v1/forum-host');
}

export async function fetchHostedBoards(options) {
  return relayClient(options).getJson('/api/v1/forum-host/boards');
}

export async function createHostedBoard({
  relayBaseUrl,
  storage,
  fetchImpl,
  intentId,
  authorDid,
  signature,
  board,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    '/api/v1/forum-host/boards',
    {
      intent_id: intentId,
      author_did: authorDid,
      signature,
      board,
    },
  );
}

export async function createHostedWebThread({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  title,
}) {
  const body = { title };
  if (typeof boardId === 'string' && boardId.trim() !== '') {
    body.board_id = boardId.trim();
  }

  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    '/api/v1/forum-host/web/threads',
    body,
    { authenticated: true },
  );
}

// POST /api/v1/forum-host/web/reports — cookie web-session authed.
// 201 {"report": ...} created; 200 {"report": ...} duplicate collapsed onto
// the reporter's existing open report.
export async function submitWebReport({
  relayBaseUrl,
  storage,
  fetchImpl,
  targetKind,
  targetRef,
  boardId,
  reasonCode,
  note,
}) {
  const { status, body } = await relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    '/api/v1/forum-host/web/reports',
    {
      target_kind: targetKind,
      target_ref: targetRef,
      board_id: boardId,
      reason_code: reasonCode,
      note: note ?? null,
    },
    { authenticated: true, withStatus: true },
  );

  return { report: body?.report ?? null, duplicate: status === 200 };
}

// GET /api/v1/forum-host/web/moderation/reports?status=open — board
// moderators only (403 not_board_moderator otherwise).
export async function fetchWebModerationReports({
  relayBaseUrl,
  storage,
  fetchImpl,
  status = 'open',
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).getJson(
    `/api/v1/forum-host/web/moderation/reports?status=${encodeURIComponent(status)}`,
    { authenticated: true },
  );
}

// POST /api/v1/forum-host/web/moderation/actions — board moderators only.
export async function submitWebModerationAction({
  relayBaseUrl,
  storage,
  fetchImpl,
  action,
  targetRef,
  boardId,
  reasonCode,
  reportId,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    '/api/v1/forum-host/web/moderation/actions',
    {
      action,
      target_ref: targetRef,
      board_id: boardId,
      reason_code: reasonCode,
      report_id: reportId ?? null,
    },
    { authenticated: true },
  );
}

// GET /api/v1/forum-host/web/moderation/actions — the audit history.
export async function fetchWebModerationActions({ relayBaseUrl, storage, fetchImpl }) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).getJson(
    '/api/v1/forum-host/web/moderation/actions',
    { authenticated: true },
  );
}

// GET /api/v1/forum-host/boards/:board_id/moderation-state — public,
// reason-coded tombstones and lock states (constitution Base Rule 6).
export async function fetchBoardModerationState({ relayBaseUrl, fetchImpl, boardId }) {
  return relayClient({ relayBaseUrl, fetchImpl }).getJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/moderation-state`,
  );
}

// Poll votes are board-scoped. The server applies the exact same VC/capability
// gate as posting and never returns a voter identity.
export async function submitBoardPollVote({ relayBaseUrl, storage, fetchImpl, boardId, pollId, optionId }) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/polls/${encodeURIComponent(pollId)}/votes`,
    { option_id: optionId },
    { authenticated: true },
  );
}

export async function fetchBoardPoll({ relayBaseUrl, fetchImpl, boardId, pollId }) {
  return relayClient({ relayBaseUrl, fetchImpl }).getJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/polls/${encodeURIComponent(pollId)}`,
  );
}

export async function fetchBoardDeliberations({ relayBaseUrl, fetchImpl, boardId }) {
  return relayClient({ relayBaseUrl, fetchImpl }).getJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations`,
  );
}

export async function fetchBoardDeliberation({
  relayBaseUrl,
  fetchImpl,
  boardId,
  deliberationId,
}) {
  return relayClient({ relayBaseUrl, fetchImpl }).getJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations/${encodeURIComponent(deliberationId)}`,
  );
}

export async function createWebDeliberation({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  title,
  prompt,
  exportMode = 'aggregates_only',
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations`,
    { deliberation: { title, prompt, export_mode: exportMode } },
    { authenticated: true },
  );
}

export async function submitWebDeliberationStatement({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  deliberationId,
  text,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations/${encodeURIComponent(deliberationId)}/statements`,
    { text },
    { authenticated: true },
  );
}

export async function submitWebDeliberationVote({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  deliberationId,
  statementId,
  stance,
  supersedesIntentId = null,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).putJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations/${encodeURIComponent(deliberationId)}/statements/${encodeURIComponent(statementId)}/vote`,
    {
      stance,
      ...(supersedesIntentId ? { supersedes_intent_id: supersedesIntentId } : {}),
    },
    { authenticated: true },
  );
}

export async function fetchWebDeliberationResponses({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  deliberationId,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations/${encodeURIComponent(deliberationId)}/responses/mine`,
    {},
    { authenticated: true },
  );
}

export async function withdrawWebDeliberationVote({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  deliberationId,
  statementId,
  supersedesIntentId,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).deleteJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations/${encodeURIComponent(deliberationId)}/statements/${encodeURIComponent(statementId)}/vote`,
    { supersedes_intent_id: supersedesIntentId },
    { authenticated: true },
  );
}

export async function requestWebDeliberationExport({
  relayBaseUrl,
  storage,
  fetchImpl,
  boardId,
  deliberationId,
  view = 'aggregates',
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    `/api/v1/forum-host/boards/${encodeURIComponent(boardId)}/deliberations/${encodeURIComponent(deliberationId)}/exports`,
    { view },
    { authenticated: true },
  );
}

function relayClient(options) {
  return createRelayApiClient(options);
}
