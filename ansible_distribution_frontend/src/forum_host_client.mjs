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
  title,
}) {
  return relayClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    '/api/v1/forum-host/web/threads',
    { title },
    { authenticated: true },
  );
}

function relayClient(options) {
  return createRelayApiClient(options);
}
