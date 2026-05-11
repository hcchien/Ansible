import { DEFAULT_LOGIN_SCOPES } from './forum_login_app.mjs';
import { RelayApiError, trimTrailingSlash } from './relay_api_client.mjs';
import {
  TRUST_TIERS,
  createWebSessionChallenge,
  fetchChallengeStatus,
  fetchCurrentWebSession,
  readWebSessionToken,
  resolveChallengePollResult,
  revokeWebSession,
} from './web_session_client.mjs';

export const DEFAULT_SESSION_VIEW_MODEL = Object.freeze({
  mode: 'public',
  authenticated: false,
  trustTier: TRUST_TIERS.anonymous,
  subjectDid: null,
  scopes: [],
  expiresAt: null,
  challenge: null,
  error: null,
  capabilities: Object.freeze({
    canRead: true,
    canPost: false,
    canReply: false,
    canRevoke: false,
    canManageProfile: false,
  }),
});

export function createSessionLifecycle({
  relayBaseUrl,
  webOrigin,
  relayOrigin = trimTrailingSlash(relayBaseUrl),
  scopes = DEFAULT_LOGIN_SCOPES,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
  webSessionClient = {
    createWebSessionChallenge,
    fetchChallengeStatus,
    fetchCurrentWebSession,
    revokeWebSession,
  },
}) {
  let state = {
    status: 'signed_out',
    challenge: null,
    session: null,
    viewModel: DEFAULT_SESSION_VIEW_MODEL,
  };

  async function restore() {
    if (!readWebSessionToken(storage)) {
      return setPublicState('signed_out');
    }

    try {
      const session = await webSessionClient.fetchCurrentWebSession({
        relayBaseUrl,
        storage,
        fetchImpl,
      });

      return setSessionState(session);
    } catch (error) {
      return setErrorState(error);
    }
  }

  async function startAppLogin() {
    const challenge = await webSessionClient.createWebSessionChallenge({
      relayBaseUrl,
      relayOrigin,
      webOrigin,
      scopes,
      fetchImpl,
    });

    state = {
      status: 'login_pending',
      challenge: normalizeChallenge(challenge),
      session: null,
      viewModel: pendingChallengeViewModel(challenge),
    };

    return state;
  }

  async function pollLoginChallenge() {
    if (!state.challenge) {
      throw new Error('startAppLogin must be called before polling');
    }

    const challenge = await webSessionClient.fetchChallengeStatus({
      relayBaseUrl,
      challengeId: state.challenge.challengeId,
      fetchImpl,
    });
    const result = resolveChallengePollResult(challenge, storage);

    if (result.state === 'approved') {
      const session = await webSessionClient.fetchCurrentWebSession({
        relayBaseUrl,
        storage,
        fetchImpl,
      });

      return setSessionState(session);
    }

    if (result.continuePolling) {
      state = {
        ...state,
        status: 'login_pending',
        viewModel: {
          ...state.viewModel,
          challenge: {
            ...state.viewModel.challenge,
            continuePolling: true,
          },
        },
      };

      return state;
    }

    return setErrorState(new Error(result.state), result.state);
  }

  async function revokeCurrentSession() {
    await webSessionClient.revokeWebSession({ relayBaseUrl, storage, fetchImpl });
    return setPublicState('signed_out');
  }

  function getState() {
    return state;
  }

  function setPublicState(status) {
    state = {
      status,
      challenge: null,
      session: null,
      viewModel: DEFAULT_SESSION_VIEW_MODEL,
    };

    return state;
  }

  function setSessionState(session) {
    state = {
      status: 'authenticated',
      challenge: null,
      session,
      viewModel: sessionViewModel(session),
    };

    return state;
  }

  function setErrorState(error, forcedType) {
    const semanticError = forcedType
      ? { type: forcedType, message: forcedType, retryable: true }
      : mapRelayErrorToSessionError(error);

    state = {
      status: semanticError.type === 'unauthenticated' ? 'signed_out' : 'error',
      challenge: null,
      session: null,
      viewModel: {
        ...DEFAULT_SESSION_VIEW_MODEL,
        error: semanticError,
      },
    };

    return state;
  }

  return {
    restore,
    startAppLogin,
    pollLoginChallenge,
    revokeCurrentSession,
    getState,
  };
}

export function sessionViewModel(session) {
  const scopes = Array.isArray(session.scopes) ? session.scopes : [];
  const tier = session.trust_tier ?? TRUST_TIERS.anonymous;

  return {
    mode: sessionModeForTrustTier(tier),
    authenticated: true,
    trustTier: tier,
    subjectDid: session.subject_did ?? null,
    scopes,
    expiresAt: session.expires_at ?? null,
    challenge: null,
    error: null,
    capabilities: capabilitiesForScopes(scopes),
  };
}

export function capabilitiesForScopes(scopes) {
  return {
    canRead: true,
    canPost: scopes.includes('forum:post'),
    canReply: scopes.includes('forum:reply'),
    canRevoke: scopes.includes('session:revoke') || scopes.length > 0,
    canManageProfile: scopes.includes('profile:write'),
  };
}

export function mapRelayErrorToSessionError(error) {
  if (error instanceof RelayApiError) {
    if (error.status === 401) {
      return { type: 'unauthenticated', message: error.message, retryable: true };
    }

    if (error.status === 403) {
      return { type: 'missing_scope', message: error.message, retryable: false };
    }

    if (error.status === 429) {
      return { type: 'rate_limited', message: error.message, retryable: true };
    }

    return { type: error.code ?? 'relay_error', message: error.message, retryable: true };
  }

  if (error instanceof TypeError) {
    return { type: 'network_unavailable', message: error.message, retryable: true };
  }

  return {
    type: 'unknown_error',
    message: error?.message ?? 'unknown_error',
    retryable: true,
  };
}

function pendingChallengeViewModel(challenge) {
  return {
    ...DEFAULT_SESSION_VIEW_MODEL,
    mode: 'login_pending',
    challenge: {
      ...normalizeChallenge(challenge),
      continuePolling: true,
    },
  };
}

function normalizeChallenge(challenge) {
  return {
    challengeId: challenge.challenge_id,
    expiresAt: challenge.expires_at,
    deepLink: challenge.deep_link,
    qrPayload: challenge.qr_payload,
  };
}

function sessionModeForTrustTier(trustTier) {
  if (trustTier === TRUST_TIERS.selfCustodyDid) {
    return 'app_approved_did';
  }

  if (trustTier === TRUST_TIERS.basicWeb || trustTier === TRUST_TIERS.webPasskey) {
    return 'hosted_web';
  }

  if (trustTier === TRUST_TIERS.verifiedHuman) {
    return 'verified_human';
  }

  return 'public';
}
