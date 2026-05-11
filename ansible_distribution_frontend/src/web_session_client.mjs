import { createRelayApiClient } from './relay_api_client.mjs';

export const WEB_SESSION_TOKEN_KEY = 'trisaura.web_session_token';

export const TRUST_TIERS = Object.freeze({
  anonymous: 'anonymous',
  basicWeb: 'basic_web',
  webPasskey: 'web_passkey',
  selfCustodyDid: 'self_custody_did',
  verifiedHuman: 'verified_human',
});

export function classifyTrustTier(trustTier) {
  const tier = trustTier ?? TRUST_TIERS.anonymous;

  return {
    trustTier: tier,
    canUseHostedWebAccount:
      tier === TRUST_TIERS.basicWeb || tier === TRUST_TIERS.webPasskey,
    isPasskeyBacked: tier === TRUST_TIERS.webPasskey,
    isSelfCustodyDid: tier === TRUST_TIERS.selfCustodyDid,
  };
}

export async function createWebSessionChallenge({
  relayBaseUrl,
  webOrigin,
  relayOrigin = relayBaseUrl,
  scopes,
  fetchImpl = globalThis.fetch,
}) {
  return createRelayApiClient({ relayBaseUrl, fetchImpl }).postJson(
    '/api/v1/web-sessions/challenges',
    {
      web_origin: webOrigin,
      relay_origin: relayOrigin,
      scopes,
    },
  );
}

export async function fetchChallengeStatus({
  relayBaseUrl,
  challengeId,
  fetchImpl = globalThis.fetch,
}) {
  return createRelayApiClient({ relayBaseUrl, fetchImpl }).getJson(
    `/api/v1/web-sessions/challenges/${encodeURIComponent(challengeId)}`,
  );
}

export async function fetchCurrentWebSession({
  relayBaseUrl,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
}) {
  return createRelayApiClient({ relayBaseUrl, storage, fetchImpl }).getJson(
    '/api/v1/web-sessions/me',
    { authenticated: true },
  );
}

export async function listWebSessions({
  relayBaseUrl,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
}) {
  return createRelayApiClient({ relayBaseUrl, storage, fetchImpl }).getJson(
    '/api/v1/web-sessions',
    { authenticated: true },
  );
}

export async function revokeWebSession({
  relayBaseUrl,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
  sessionToken,
} = {}) {
  const body = sessionToken ? { session_token: sessionToken } : {};
  const result = await createRelayApiClient({ relayBaseUrl, storage, fetchImpl }).postJson(
    '/api/v1/web-sessions/revoke',
    body,
    { authenticated: true },
  );

  if (!sessionToken || sessionToken === readWebSessionToken(storage)) {
    clearWebSessionToken(storage);
  }

  return result;
}

export function resolveChallengePollResult(challenge, storage) {
  switch (challenge.status) {
    case 'pending':
      return {
        state: 'pending',
        continuePolling: true,
        authenticated: false,
        retryable: false,
      };

    case 'approved':
      if (!challenge.session_token) {
        throw new Error('approved web-session challenge is missing session_token');
      }

      storeWebSessionToken(storage, challenge.session_token);

      return {
        state: 'approved',
        continuePolling: false,
        authenticated: true,
        retryable: false,
        trustTier: challenge.trust_tier ?? TRUST_TIERS.selfCustodyDid,
      };

    case 'rejected':
      clearWebSessionToken(storage);
      return {
        state: 'rejected',
        continuePolling: false,
        authenticated: false,
        retryable: true,
      };

    case 'expired':
      clearWebSessionToken(storage);
      return {
        state: 'expired',
        continuePolling: false,
        authenticated: false,
        retryable: true,
      };

    default:
      throw new Error(`unknown web-session challenge status: ${challenge.status}`);
  }
}

export function storeWebSessionToken(storage, sessionToken) {
  storage.setItem(WEB_SESSION_TOKEN_KEY, sessionToken);
}

export function readWebSessionToken(storage) {
  return storage.getItem(WEB_SESSION_TOKEN_KEY);
}

export function clearWebSessionToken(storage) {
  storage.removeItem(WEB_SESSION_TOKEN_KEY);
}
