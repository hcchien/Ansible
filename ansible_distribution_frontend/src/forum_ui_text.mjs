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

// Localized labels for the relay report-reason enum. The codes themselves are
// the relay contract; only the labels are frontend concerns.
const REASON_CODE_LABELS = Object.freeze({
  spam: 'reason.spam',
  harassment: 'reason.harassment',
  illegal_content: 'reason.illegalContent',
  off_topic: 'reason.offTopic',
  impersonation: 'reason.impersonation',
  other: 'reason.other',
});

const MODERATION_ACTION_LABELS = Object.freeze({
  dismiss_report: 'moderation.action.dismissReport',
  remove_post_from_board: 'moderation.action.removePostFromBoard',
  lock_thread: 'moderation.action.lockThread',
  unlock_thread: 'moderation.action.unlockThread',
  hide_context_note: 'moderation.action.hideContextNote',
});

const TARGET_KIND_LABELS = Object.freeze({
  post: 'moderation.target.post',
  thread: 'moderation.target.thread',
  context_note: 'moderation.target.contextNote',
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

export function reasonCodeLabel(reasonCode) {
  const key = REASON_CODE_LABELS[reasonCode];
  return key ? t(key) : reasonCode ?? '';
}

export function moderationActionLabel(action) {
  const key = MODERATION_ACTION_LABELS[action];
  return key ? t(key) : action ?? '';
}

export function targetKindLabel(targetKind) {
  const key = TARGET_KIND_LABELS[targetKind];
  return key ? t(key) : targetKind ?? '';
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

  if (error.type === ERROR_TYPES.notBoardModerator) {
    return {
      tone: 'warning',
      title: t('error.notBoardModerator.title'),
      message: t('error.notBoardModerator.message'),
    };
  }

  if (error.type === ERROR_TYPES.threadLocked) {
    return {
      tone: 'warning',
      title: t('error.threadLocked.title'),
      message: t('error.threadLocked.message', {
        reason: reasonCodeLabel(error.detail?.reasonCode ?? ''),
      }),
    };
  }

  if (
    error.type === ERROR_TYPES.invalidRequest &&
    ['invalid_reason_code', 'note_required', 'unknown_target'].includes(error.code)
  ) {
    return {
      tone: 'warning',
      title: t('error.invalidReport.title'),
      message:
        error.code === 'note_required'
          ? t('error.noteRequired.message')
          : error.code === 'unknown_target'
            ? t('error.unknownTarget.message')
            : t('error.invalidReport.message'),
    };
  }

  return {
    tone: 'danger',
    title: t('error.forum.title'),
    message: error.message || t('error.forum.message'),
  };
}
