import { ERROR_TYPES } from './error_taxonomy.mjs';
import { t } from './web_i18n.mjs';

const SCOPE_LABEL_KEYS = Object.freeze({
  'forum:read': 'scope.forum.read',
  'forum:post': 'scope.forum.post',
  'forum:reply': 'scope.forum.reply',
  'identity:display': 'scope.identity.display',
  'session:revoke': 'scope.session.revoke',
});

const TRUST_TIER_LABELS = Object.freeze({
  anonymous: 'trust.anonymous',
  basic_web: 'trust.basicWeb',
  web_passkey: 'trust.webPasskey',
  self_custody_did: 'trust.selfCustodyDid',
  verified_human: 'trust.verifiedHuman',
});

export function shortIdentity(value) {
  if (!value) return t('common.anonymous');
  if (value.length <= 16) return value;
  return `${value.slice(0, 7)}...${value.slice(-6)}`;
}

export function trustTierLabel(value) {
  const key = TRUST_TIER_LABELS[value];
  return key ? t(key) : value ?? t('common.anonymous');
}

export function formatScope(scope) {
  const key = SCOPE_LABEL_KEYS[scope];
  return key ? t(key) : scope;
}

export function formatExpiry(value) {
  if (!value) return t('common.noExpiry');
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
}

export function describeError(error) {
  if (!error) return null;

  if (error.type === ERROR_TYPES.missingScope) {
    const requiredScope = error.detail?.requiredScope;
    const message = requiredScope
      ? t('error.signInRequired.scopeMessage', { scope: formatScope(requiredScope) })
      : t('error.signInRequired.genericMessage');

    return {
      tone: 'warning',
      title: t('error.signInRequired.title'),
      message,
    };
  }

  if (error.type === ERROR_TYPES.postingRequiresTier) {
    const requiredTier = error.detail?.requiredTier ?? 'verified_human';

    return {
      tone: 'warning',
      title: t('error.postingRequiresTier.title'),
      message: t('error.postingRequiresTier.message', {
        tier: trustTierLabel(requiredTier),
      }),
    };
  }

  if (error.type === ERROR_TYPES.unauthenticated) {
    return {
      tone: 'danger',
      title: t('error.sessionUnavailable.title'),
      message: t('error.sessionUnavailable.message'),
    };
  }

  if (error.type === ERROR_TYPES.notFound) {
    return {
      tone: 'danger',
      title: t('error.notFound.title'),
      message: t('error.notFound.message'),
    };
  }

  if (error.type === ERROR_TYPES.rateLimited) {
    return {
      tone: 'warning',
      title: t('error.rateLimited.title'),
      message: t('error.rateLimited.message'),
    };
  }

  return {
    tone: 'danger',
    title: t('error.forum.title'),
    message: error.message || t('error.forum.message'),
  };
}
