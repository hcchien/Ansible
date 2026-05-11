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
  assertFetch(fetchImpl);

  const response = await fetchImpl(
    `${trimTrailingSlash(relayBaseUrl)}/api/v1/web-sessions/challenges`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        web_origin: webOrigin,
        relay_origin: relayOrigin,
        scopes,
      }),
    },
  );

  return parseJsonResponse(response);
}

export async function fetchChallengeStatus({
  relayBaseUrl,
  challengeId,
  fetchImpl = globalThis.fetch,
}) {
  assertFetch(fetchImpl);

  const response = await fetchImpl(
    `${trimTrailingSlash(
      relayBaseUrl,
    )}/api/v1/web-sessions/challenges/${encodeURIComponent(challengeId)}`,
    { method: 'GET' },
  );

  return parseJsonResponse(response);
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

function assertFetch(fetchImpl) {
  if (typeof fetchImpl !== 'function') {
    throw new TypeError('fetchImpl is required');
  }
}

async function parseJsonResponse(response) {
  const body = await response.json();

  if (!response.ok) {
    const message = body?.error ?? `request failed with HTTP ${response.status}`;
    throw new Error(message);
  }

  return body;
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}
