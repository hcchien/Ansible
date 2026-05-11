import { createHostedWebThread } from './forum_host_client.mjs';
import {
  createWebSessionChallenge,
  fetchChallengeStatus,
  resolveChallengePollResult,
} from './web_session_client.mjs';

export const DEFAULT_LOGIN_SCOPES = Object.freeze([
  'forum:read',
  'forum:post',
  'forum:reply',
  'identity:display',
]);

export function createForumLoginController({
  relayBaseUrl,
  webOrigin,
  relayOrigin = trimTrailingSlash(relayBaseUrl),
  scopes = DEFAULT_LOGIN_SCOPES,
  storage = globalThis.localStorage,
  client = { createWebSessionChallenge, fetchChallengeStatus },
  fetchImpl = globalThis.fetch,
}) {
  let state = {
    status: 'signed_out',
    authenticated: false,
    challenge: null,
    trustTier: null,
    error: null,
  };

  async function startLogin() {
    state = { ...state, status: 'starting', error: null };

    const challenge = await client.createWebSessionChallenge({
      relayBaseUrl,
      relayOrigin,
      webOrigin,
      scopes,
    });

    state = {
      status: 'pending',
      authenticated: false,
      challenge: normalizeChallenge(challenge),
      trustTier: null,
      error: null,
    };

    return state;
  }

  async function pollOnce() {
    if (!state.challenge) {
      throw new Error('startLogin must be called before polling');
    }

    const challenge = await client.fetchChallengeStatus({
      relayBaseUrl,
      challengeId: state.challenge.challengeId,
    });
    const result = resolveChallengePollResult(challenge, storage);

    state = {
      ...state,
      status: result.state,
      authenticated: result.authenticated,
      trustTier: result.trustTier ?? state.trustTier,
      error: null,
    };

    return state;
  }

  async function createThreadSmoke({ title }) {
    return createHostedWebThread({ relayBaseUrl, storage, fetchImpl, title });
  }

  function getState() {
    return state;
  }

  return { startLogin, pollOnce, createThreadSmoke, getState };
}

function normalizeChallenge(challenge) {
  return {
    challengeId: challenge.challenge_id,
    expiresAt: challenge.expires_at,
    deepLink: challenge.deep_link,
    qrPayload: challenge.qr_payload,
  };
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}
