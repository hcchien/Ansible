const MAX_MENTIONS = 10;

export function mentionToken(actor = {}, { selections = [] } = {}) {
  const did = String(actor.did ?? '').trim();
  const handle = String(actor.handle ?? '').trim().replace(/^@/, '');
  const displayName = String(actor.displayName ?? '').trim().replace(/\s+/g, ' ');
  const preferred = `@${displayName || handle || shortDid(did)}`;
  const collision = selections.some((selection) => {
    const selectedDid = String(selection?.did ?? '').trim();
    const selectedToken = String(selection?.token ?? mentionToken(selection)).trim();
    return selectedDid !== did && selectedToken.toLowerCase() === preferred.toLowerCase();
  });
  if (!collision) return preferred;
  return handle ? `${preferred} (@${handle})` : `${preferred} (${shortDid(did)})`;
}

export function insertMentionAtSelection(text, selectionStart, selectionEnd, actor) {
  const source = String(text ?? '');
  const start = clampSelection(selectionStart, source.length);
  const end = Math.max(start, clampSelection(selectionEnd, source.length));
  const token = String(actor?.token ?? mentionToken(actor)).trim();
  const prefix = start > 0 && !/\s/.test(source[start - 1]) ? ' ' : '';
  const suffix = end < source.length && /\s/.test(source[end]) ? '' : ' ';
  const replacement = `${prefix}${token}${suffix}`;

  return {
    text: source.slice(0, start) + replacement + source.slice(end),
    cursor: start + replacement.length,
    token,
  };
}

export function activeMentionDids({
  body,
  selections = [],
  excludingDid = null,
  limit = MAX_MENTIONS,
} = {}) {
  const text = String(body ?? '');
  const excluded = String(excludingDid ?? '').trim();
  const seen = new Set();
  const active = [];

  for (const selection of selections) {
    const did = String(selection?.did ?? '').trim();
    const token = String(selection?.token ?? mentionToken(selection)).trim();
    if (!did || did === excluded || seen.has(did) || !containsMentionToken(text, token)) continue;
    seen.add(did);
    active.push(did);
    if (active.length >= limit) break;
  }
  return active;
}

export function normalizeMentionDids(values, { excludingDid = null, limit = MAX_MENTIONS } = {}) {
  const excluded = String(excludingDid ?? '').trim();
  const seen = new Set();
  const normalized = [];
  for (const value of Array.isArray(values) ? values : []) {
    const did = String(value ?? '').trim();
    if (!did.startsWith('did:') || did === excluded || seen.has(did)) continue;
    seen.add(did);
    normalized.push(did);
    if (normalized.length >= limit) break;
  }
  return normalized;
}

function containsMentionToken(text, token) {
  if (!token) return false;
  const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|\\s)${escaped}(?=\\s|[.,!?，。！？、:;；：)]|$)`, 'i').test(text);
}

function clampSelection(value, length) {
  const number = Number(value);
  if (!Number.isFinite(number)) return length;
  return Math.min(length, Math.max(0, Math.trunc(number)));
}

function shortDid(value) {
  const did = String(value ?? '').trim();
  if (did.length <= 18) return did;
  return `${did.slice(0, 8)}…${did.slice(-6)}`;
}
