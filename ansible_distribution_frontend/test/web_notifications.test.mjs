import assert from 'node:assert/strict';

import {
  createWebNotificationReadStore,
  projectWebReplyNotifications,
} from '../src/web_notifications.mjs';

const feed = {
  boardId: 'general',
  items: [
    {
      entity_type: 'thread',
      op_type: 'insert',
      entity_id: 'thread-1',
      board_id: 'general',
      author_did: 'did:plc:legacy-me',
      created_at: '2026-08-22T01:00:00Z',
      payload: { title: 'My migrated thread' },
    },
    {
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'my-post',
      board_id: 'general',
      author_did: 'did:elix:me',
      created_at: '2026-08-22T01:01:00Z',
      payload: { threadId: 'thread-1', content: 'mine' },
    },
    {
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'reply-thread',
      board_id: 'general',
      author_did: 'did:elix:alice',
      author_display_name: 'Alice',
      author_handle: 'alice.elix.cool',
      created_at: '2026-08-22T01:02:00Z',
      payload: { threadId: 'thread-1', content: 'reply' },
    },
    {
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'reply-post',
      board_id: 'general',
      author_did: 'did:elix:bob',
      created_at: '2026-08-22T01:03:00Z',
      payload: {
        threadId: 'thread-1',
        parentPostId: 'my-post',
        content: 'nested reply',
      },
    },
    {
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'mention-me',
      board_id: 'general',
      author_did: 'did:elix:carol',
      created_at: '2026-08-22T01:05:00Z',
      payload: {
        threadId: 'thread-1',
        content: 'hello @me',
        mentionDids: ['did:elix:me'],
      },
    },
    {
      entity_type: 'post',
      op_type: 'insert',
      entity_id: 'self-reply',
      board_id: 'general',
      author_did: 'did:elix:me',
      created_at: '2026-08-22T01:04:00Z',
      payload: { threadId: 'thread-1', content: 'self' },
    },
  ],
};

const projected = projectWebReplyNotifications({
  feeds: [feed],
  subjectDids: ['did:elix:me', 'did:plc:legacy-me'],
  readIds: ['reply:reply-thread'],
});
assert.deepEqual(
  projected.map(({ id, type, isRead }) => ({ id, type, isRead })),
  [
    { id: 'mention:mention-me', type: 'mention', isRead: false },
    { id: 'reply:reply-post', type: 'reply_to_post', isRead: false },
    { id: 'reply:reply-thread', type: 'reply_to_thread', isRead: true },
  ],
);
assert.equal(projected.find((item) => item.id === 'reply:reply-thread').actorDisplayName, 'Alice');
console.log('ok - projects Forum Host replies for canonical and legacy DIDs');

const values = new Map();
const storage = {
  getItem(key) {
    return values.get(key) ?? null;
  },
  setItem(key, value) {
    values.set(key, value);
  },
};
const readStore = createWebNotificationReadStore({ storage });
readStore.markRead('did:elix:me', 'reply:one');
readStore.markAllRead('did:elix:me', ['reply:two']);
assert.deepEqual(readStore.readIds('did:elix:me'), ['reply:one', 'reply:two']);
assert.deepEqual(readStore.readIds('did:elix:other'), []);
console.log('ok - keeps read state browser-local and isolated per DID');
