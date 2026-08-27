import { createRelayApiClient } from './relay_api_client.mjs';

// The AppView is a separate read service from the relay. External (federated)
// content is curated, never-verified, and surfaced ONLY through this explicit
// query path — it never rides the relay's verified read contract.
//
// The browser reaches the AppView through the frontend server's same-origin
// `/appview/*` proxy (see server.mjs APPVIEW_URL). Anonymous + public: no
// session cookie is sent. A failure here must NEVER take a board page down,
// so callers wrap this in failure-tolerant code (see forum_data_adapter).
//
// Contract (committed in the AppView):
//   GET /appview/api/v1/boards/:board_id/external?cursor=&limit=
//   -> { items: [{ log_id, op_id, board_id, content, created_at,
//                  external_actor_uri, external_instance, compliance_level,
//                  reputation_tier: "external_unverified", external: true,
//                  origin: "activitypub" }],
//        next_cursor, has_more }
export async function fetchBoardExternalContent({
  appViewBaseUrl,
  fetchImpl,
  boardId,
  cursor = null,
  limit = null,
}) {
  const query = new URLSearchParams();
  if (cursor != null && cursor !== '') {
    query.set('cursor', String(cursor));
  }
  if (limit != null && limit !== '') {
    query.set('limit', String(limit));
  }
  const suffix = query.toString() ? `?${query.toString()}` : '';

  return createRelayApiClient({ relayBaseUrl: appViewBaseUrl, fetchImpl }).getJson(
    `/api/v1/boards/${encodeURIComponent(boardId)}/external${suffix}`,
  );
}

export async function fetchBoardFeed({
  appViewBaseUrl,
  fetchImpl = globalThis.fetch,
  boardId,
  cursor = null,
  limit = null,
}) {
  const query = new URLSearchParams();
  query.set('board_id', String(boardId));
  if (cursor != null && cursor !== '') {
    query.set('cursor', String(cursor));
  }
  if (limit != null && limit !== '') {
    query.set('limit', String(limit));
  }
  const suffix = query.toString() ? `?${query.toString()}` : '';

  return createRelayApiClient({ relayBaseUrl: appViewBaseUrl, fetchImpl }).getJson(
    `/api/v1/board-feed${suffix}`,
  );
}

export async function fetchThreadFeed({
  appViewBaseUrl,
  fetchImpl = globalThis.fetch,
  threadId,
  cursor = null,
  limit = null,
}) {
  const query = new URLSearchParams();
  if (cursor != null && cursor !== '') {
    query.set('cursor', String(cursor));
  }
  if (limit != null && limit !== '') {
    query.set('limit', String(limit));
  }
  const suffix = query.toString() ? `?${query.toString()}` : '';

  return createRelayApiClient({ relayBaseUrl: appViewBaseUrl, fetchImpl }).getJson(
    `/api/v1/thread/${encodeURIComponent(threadId)}${suffix}`,
  );
}

// Public profile projection: only fields deliberately published in a signed
// profile op are returned by AppView. The DID remains the stable identifier;
// these presentation fields never participate in browser authorization.
export async function fetchPublicProfile({
  appViewBaseUrl,
  fetchImpl = globalThis.fetch,
  did,
}) {
  return createRelayApiClient({ relayBaseUrl: appViewBaseUrl, fetchImpl }).getJson(
    `/api/v1/profiles/${encodeURIComponent(did)}`,
  );
}

export async function fetchAuthorTimeline({
  appViewBaseUrl,
  fetchImpl = globalThis.fetch,
  did,
  cursor = null,
  limit = 100,
}) {
  return createRelayApiClient({ relayBaseUrl: appViewBaseUrl, fetchImpl }).postJson(
    '/api/v1/timeline',
    {
      dids: [did],
      ...(cursor == null || cursor === '' ? {} : { cursor }),
      limit,
    },
  );
}
