import { createRelayApiClient } from './relay_api_client.mjs';

const encoder = new TextEncoder();

export async function createPasskeySignedThread({
  relayBaseUrl,
  storage,
  fetchImpl,
  credentials = globalThis.navigator?.credentials,
  cryptoImpl = globalThis.crypto,
  authorDid,
  targetForumHost,
  boardId,
  boardPolicyVersion,
  title,
  visibility = 'public',
  federate = true,
  now = () => new Date(),
}) {
  return createPasskeySignedOperation({
    relayBaseUrl,
    storage,
    fetchImpl,
    credentials,
    cryptoImpl,
    authorDid,
    targetForumHost,
    boardId,
    boardPolicyVersion,
    action: 'forum.publish',
    entityType: 'thread',
    payload: { title: String(title).trim() },
    visibility,
    federate,
    now,
  });
}

export async function createPasskeySignedOperation({
  relayBaseUrl,
  storage,
  fetchImpl,
  credentials = globalThis.navigator?.credentials,
  cryptoImpl = globalThis.crypto,
  authorDid,
  targetForumHost,
  boardId,
  boardPolicyVersion,
  action,
  entityType,
  entityId,
  parentId = null,
  expectedPreviousRevision = null,
  payload,
  visibility = 'public',
  federate = true,
  now = () => new Date(),
}) {
  if (!credentials?.get || !cryptoImpl?.subtle || !cryptoImpl?.getRandomValues) {
    throw publicationError('webauthn_unavailable');
  }

  const operation = await buildWebPublicationOperation({
    cryptoImpl,
    authorDid,
    targetForumHost,
    boardId,
    boardPolicyVersion,
    action,
    entityType,
    entityId,
    parentId,
    expectedPreviousRevision,
    payload,
    visibility,
    federate,
    now,
  });
  const operationHash = await sha256Hex(canonicalJson(operation), cryptoImpl);
  const client = createRelayApiClient({ relayBaseUrl, storage, fetchImpl });

  const challenge = await client.postJson(
    '/api/v1/web-publication/challenges',
    { operation, operation_hash: operationHash },
    { authenticated: true },
  );
  const publicKey = decodeRequestOptions(challenge.publicKey);

  let assertion;
  try {
    assertion = await credentials.get({ publicKey });
  } catch (error) {
    if (error?.name === 'NotAllowedError' || error?.name === 'AbortError') {
      throw publicationError('passkey_cancelled', { cause: error });
    }
    throw publicationError('webauthn_verification_failed', { cause: error });
  }

  const credential = serializeAssertion(assertion);
  try {
    return await client.postJson(
      '/api/v1/web-publication/operations',
      {
        challenge_id: challenge.challenge_id,
        operation,
        operation_hash: operationHash,
        credential,
      },
      { authenticated: true },
    );
  } catch (error) {
    if (!isAmbiguousTransportError(error)) throw error;

    try {
      return await client.getJson(
        `/api/v1/web-publication/operations/${encodeURIComponent(operation.operation_id)}`,
        { authenticated: true },
      );
    } catch {
      throw error;
    }
  }
}

export async function buildWebPublicationOperation({
  cryptoImpl = globalThis.crypto,
  authorDid,
  targetForumHost,
  boardId,
  boardPolicyVersion,
  action = 'forum.publish',
  entityType = 'thread',
  entityId,
  parentId = null,
  expectedPreviousRevision = null,
  payload,
  title,
  visibility = 'public',
  federate = true,
  now = () => new Date(),
}) {
  const createdAt = now();
  const expiresAt = new Date(createdAt.getTime() + 5 * 60 * 1000);
  const normalizedPayload = payload ?? { title: String(title).trim() };
  const payloadHash = await sha256Hex(canonicalJson(normalizedPayload), cryptoImpl);

  return {
    type: 'io.trisaura.webPublicationOperation',
    version: 1,
    operation_id: `wop_${randomId(cryptoImpl)}`,
    author_did: authorDid,
    action,
    target_forum_host: normalizeOrigin(targetForumHost),
    board_id: boardId,
    entity_type: entityType,
    entity_id: entityId || `${entityType}_${randomId(cryptoImpl)}`,
    parent_id: parentId,
    expected_previous_revision: expectedPreviousRevision,
    visibility,
    federate: Boolean(federate),
    payload: normalizedPayload,
    payload_hash: payloadHash,
    board_policy_version: Number(boardPolicyVersion),
    created_at: createdAt.toISOString(),
    expires_at: expiresAt.toISOString(),
    nonce: randomId(cryptoImpl),
  };
}

export function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

export async function sha256Hex(value, cryptoImpl = globalThis.crypto) {
  const digest = await cryptoImpl.subtle.digest('SHA-256', encoder.encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export function decodeRequestOptions(options) {
  return {
    ...options,
    challenge: fromBase64Url(options.challenge),
    allowCredentials: (options.allowCredentials ?? []).map((descriptor) => ({
      ...descriptor,
      id: fromBase64Url(descriptor.id),
    })),
  };
}

export function serializeAssertion(credential) {
  return {
    id: credential.id,
    rawId: toBase64Url(credential.rawId),
    type: credential.type,
    response: {
      clientDataJSON: toBase64Url(credential.response.clientDataJSON),
      authenticatorData: toBase64Url(credential.response.authenticatorData),
      signature: toBase64Url(credential.response.signature),
      userHandle: credential.response.userHandle
        ? toBase64Url(credential.response.userHandle)
        : null,
    },
  };
}

function randomId(cryptoImpl) {
  const bytes = new Uint8Array(16);
  cryptoImpl.getRandomValues(bytes);
  return toBase64Url(bytes);
}

function normalizeOrigin(value) {
  const url = new URL(value);
  return url.origin;
}

function fromBase64Url(value) {
  const normalized = String(value).replace(/-/g, '+').replace(/_/g, '/');
  const padding = '='.repeat((4 - (normalized.length % 4)) % 4);
  const binary = globalThis.atob(`${normalized}${padding}`);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function toBase64Url(value) {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return globalThis
    .btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function isAmbiguousTransportError(error) {
  return error?.code === 'network_unavailable' || error?.name === 'TypeError';
}

function publicationError(code, extra = {}) {
  return Object.assign(new Error(code), { code, ...extra });
}
