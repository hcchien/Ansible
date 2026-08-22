const STORAGE_PREFIX = 'elix.notifications.read.v1';
const MAX_READ_IDS = 1000;

export function projectWebReplyNotifications({ feeds = [], subjectDids = [], readIds = [] }) {
  const localDids = new Set(
    subjectDids.map((did) => String(did ?? '').trim()).filter(Boolean),
  );
  if (localDids.size === 0) return [];

  const read = new Set(readIds);
  const threads = new Map();
  const posts = new Map();

  for (const feed of feeds) {
    for (const item of feed.items ?? []) {
      if (item?.op_type !== 'insert') continue;
      if (item.entity_type === 'thread') {
        threads.set(item.entity_id, item);
      } else if (item.entity_type === 'post') {
        posts.set(item.entity_id, item);
      }
    }
  }

  const notifications = [];
  for (const feed of feeds) {
    for (const item of feed.items ?? []) {
      if (item?.entity_type !== 'post' || item.op_type !== 'insert') continue;
      if (localDids.has(item.author_did)) continue;

      const payload = item.payload ?? {};
      const threadId = payload.threadId ?? payload.thread_id ?? item.thread_id ?? null;
      const parentPostId =
        payload.parentPostId ?? payload.parent_post_id ?? item.parent_post_id ?? null;
      const parent = parentPostId ? posts.get(parentPostId) : null;
      const thread = threadId ? threads.get(threadId) : null;
      const type = parent && localDids.has(parent.author_did)
        ? 'reply_to_post'
        : thread && localDids.has(thread.author_did)
          ? 'reply_to_thread'
          : null;
      if (!type || !threadId) continue;

      const id = `reply:${item.entity_id}`;
      notifications.push({
        id,
        type,
        actorDid: item.author_did ?? '',
        actorHandle: item.author_handle ?? payload.author_handle ?? null,
        boardId: item.board_id ?? feed.boardId ?? thread?.board_id ?? '',
        threadId,
        postId: item.entity_id,
        createdAt: item.created_at ?? null,
        isRead: read.has(id),
      });
    }
  }

  return notifications.sort(
    (left, right) => Date.parse(right.createdAt ?? 0) - Date.parse(left.createdAt ?? 0),
  );
}

export function createWebNotificationReadStore({ storage }) {
  function readIds(subjectDid) {
    try {
      const decoded = JSON.parse(storage.getItem(storageKey(subjectDid)) ?? '[]');
      return Array.isArray(decoded) ? decoded.filter((id) => typeof id === 'string') : [];
    } catch {
      return [];
    }
  }

  function markRead(subjectDid, notificationId) {
    const ids = new Set(readIds(subjectDid));
    ids.add(notificationId);
    write(subjectDid, [...ids]);
  }

  function markAllRead(subjectDid, notificationIds) {
    const ids = new Set(readIds(subjectDid));
    for (const id of notificationIds) ids.add(id);
    write(subjectDid, [...ids]);
  }

  function write(subjectDid, ids) {
    const bounded = ids.slice(-MAX_READ_IDS);
    storage.setItem(storageKey(subjectDid), JSON.stringify(bounded));
  }

  return { readIds, markRead, markAllRead };
}

function storageKey(subjectDid) {
  return `${STORAGE_PREFIX}.${encodeURIComponent(String(subjectDid ?? 'anonymous'))}`;
}
