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
    { authenticated: true },
  );
}

export async function fetchCurrentWebSession({
  relayBaseUrl,
  // storage is accepted for backward compatibility but no longer used for auth.
  storage: _storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
}) {
  return createRelayApiClient({ relayBaseUrl, fetchImpl }).getJson(
    '/api/v1/web-sessions/me',
    { authenticated: true },
  );
}

export async function listWebSessions({
  relayBaseUrl,
  // storage is accepted for backward compatibility but no longer used for auth.
  storage: _storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
}) {
  return createRelayApiClient({ relayBaseUrl, fetchImpl }).getJson(
    '/api/v1/web-sessions',
    { authenticated: true },
  );
}

export async function revokeWebSession({
  relayBaseUrl,
  // storage is accepted for backward compatibility but no longer used for auth.
  // The relay clears the httpOnly session cookie on successful revocation.
  storage: _storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
  sessionId,
  sessionToken,
} = {}) {
  let body = {};
  if (sessionId) {
    body = { session_id: sessionId };
  } else if (sessionToken) {
    body = { session_token: sessionToken };
  }

  return createRelayApiClient({ relayBaseUrl, fetchImpl }).postJson(
    '/api/v1/web-sessions/revoke',
    body,
    { authenticated: true },
  );
}

export function resolveChallengePollResult(challenge, _storage) {
  // Note: _storage is accepted for backward compatibility but is no longer used.
  // Session tokens are now managed via httpOnly cookies set by the relay server.
  switch (challenge.status) {
    case 'pending':
      return {
        state: 'pending',
        continuePolling: true,
        authenticated: false,
        retryable: false,
      };

    case 'approved':
      // The relay sets an httpOnly cookie on the poll_challenge response when approved.
      // No token handling needed here — the cookie is set automatically by the server.
      return {
        state: 'approved',
        continuePolling: false,
        authenticated: true,
        retryable: false,
        trustTier: challenge.trust_tier ?? TRUST_TIERS.selfCustodyDid,
      };

    case 'rejected':
      return {
        state: 'rejected',
        continuePolling: false,
        authenticated: false,
        retryable: true,
      };

    case 'expired':
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

/**
 * @deprecated Session tokens are now managed via httpOnly cookies. This function is a no-op.
 */
export function storeWebSessionToken(_storage, _sessionToken) {
  // no-op: session tokens are now set as httpOnly cookies by the relay server
}

/**
 * @deprecated Session tokens are now managed via httpOnly cookies. Always returns null.
 */
export function readWebSessionToken(_storage) {
  return null;
}

/**
 * @deprecated Session tokens are now managed via httpOnly cookies. This function is a no-op.
 * Use revokeWebSession() to clear the session, which causes the relay to clear the cookie.
 */
export function clearWebSessionToken(_storage) {
  // no-op: the relay clears the httpOnly cookie on revocation
}
