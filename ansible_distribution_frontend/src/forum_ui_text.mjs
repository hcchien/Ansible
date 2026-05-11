import { ERROR_TYPES } from './error_taxonomy.mjs';

const SCOPE_LABELS = Object.freeze({
  'forum:read': 'Read forum',
  'forum:post': 'Post threads',
  'forum:reply': 'Reply',
  'identity:display': 'Display identity',
  'session:revoke': 'Revoke sessions',
});

const TRUST_TIER_LABELS = Object.freeze({
  anonymous: 'Anonymous',
  basic_web: 'Basic web',
  web_passkey: 'Web passkey',
  self_custody_did: 'Self-custody DID',
  verified_human: 'Verified human',
});

export function shortIdentity(value) {
  if (!value) return 'Anonymous';
  if (value.length <= 16) return value;
  return `${value.slice(0, 7)}...${value.slice(-6)}`;
}

export function trustTierLabel(value) {
  return TRUST_TIER_LABELS[value] ?? value ?? 'Anonymous';
}

export function formatScope(scope) {
  return SCOPE_LABELS[scope] ?? scope;
}

export function formatExpiry(value) {
  if (!value) return 'No expiry';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
}

export function describeError(error) {
  if (!error) return null;

  if (error.type === ERROR_TYPES.missingScope) {
    const requiredScope = error.detail?.requiredScope;
    const message = requiredScope
      ? `This action needs the ${formatScope(requiredScope)} scope.`
      : 'This action needs an additional forum scope.';

    return {
      tone: 'warning',
      title: 'Sign in required',
      message,
    };
  }

  if (error.type === ERROR_TYPES.unauthenticated) {
    return {
      tone: 'danger',
      title: 'Session unavailable',
      message: 'Start a new app-approved browser session to continue.',
    };
  }

  if (error.type === ERROR_TYPES.notFound) {
    return {
      tone: 'danger',
      title: 'Not found',
      message: 'This forum route or resource is unavailable.',
    };
  }

  if (error.type === ERROR_TYPES.rateLimited) {
    return {
      tone: 'warning',
      title: 'Rate limited',
      message: 'Wait before retrying this forum action.',
    };
  }

  return {
    tone: 'danger',
    title: 'Forum error',
    message: error.message || 'The forum frontend could not complete the request.',
  };
}
