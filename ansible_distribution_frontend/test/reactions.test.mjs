import assert from 'node:assert/strict';
import { buildThreadsFromFeed, createForumDataAdapter } from '../src/forum_data_adapter.mjs';
import { renderReactions } from '../src/forum_page_renderers.mjs';

const content = [
  { entity_type: 'thread', entity_id: 't', op_type: 'insert', payload: { title: 'Title' }, board_id: '1' },
  { entity_type: 'post', entity_id: 'p', op_type: 'insert', payload: { threadId: 't', content: 'Reply' } },
];
const reaction = (id, author, type, op = 'insert', target = 'p', log = 1) => ({
  entity_type: 'reaction', entity_id: id, author_did: author, op_type: op, op_id: `op-${log}`, log_id: log,
  payload: { targetType: target === 't' ? 'thread' : 'post', targetId: target, reactionType: type },
});
const threads = buildThreadsFromFeed([...content,
  reaction('r1', 'did:a', 'thumbsUp'), reaction('r1', 'did:a', 'happy', 'update', 'p', 2),
  reaction('r2', 'did:b', 'sad', 'insert', 'p', 3),
  reaction('r3', 'did:c', 'angry', 'insert', 'p', 4),
  reaction('r2', 'did:b', 'sad', 'delete', 'p', 5),
  reaction('rt', 'did:a', 'sad', 'insert', 't', 6),
]);
assert.equal(threads[0].posts[0].likeCount, 2);
assert.deepEqual(threads[0].posts[0].reactions.map((r) => [r.authorDid, r.reactionType]), [['did:a', 'happy'], ['did:c', 'angry']]);
assert.equal(threads[0].reactions[0].reactionType, 'sad');
const migrated = buildThreadsFromFeed([...content,
  { ...reaction('old', 'did:old', 'thumbsUp'), canonical_author_did: 'did:new' },
  reaction('new', 'did:new', 'happy', 'insert', 'p', 2),
]);
assert.equal(migrated[0].posts[0].likeCount, 1);
assert.equal(migrated[0].posts[0].reactions[0].reactionType, 'happy');

const session = { subjectDid: 'did:a', authenticated: true, capabilities: { canReact: true, canEdit: true, canDelete: true } };
const html = renderReactions(threads[0].posts[0], 'post', { boardId: '1', session });
assert.equal((html.match(/data-action="react"/g) ?? []).length, 5);
assert.match(html, /data-target-id="p"/);
assert.match(html, /data-reaction-type="happy" aria-pressed="true"/);
assert.match(html, /data-existing-id="r1" data-revision="op-2"/);
assert.match(html, /#\/profiles\/did%3Aa/);
assert.doesNotMatch(renderReactions(threads[0], 'thread'), /data-action="react"/);
const escaped = renderReactions({ id: 'p', reactions: [{ authorDid: 'did:evil', authorDisplayName: '<img src=x onerror=alert(1)>', reactionType: 'sad' }] }, 'post');
assert.doesNotMatch(escaped, /<img/);
assert.match(escaped, /&lt;img/);

const calls = [];
const adapter = createForumDataAdapter({ relayBaseUrl: 'https://relay.example', appViewBaseUrl: 'https://view.example',
  forumHostClient: {
    fetchForumHostInfo: async () => ({ canonical_base_url: 'https://relay.example' }),
    fetchHostedBoards: async () => ({ boards: [{ board_id: 1, access_policy_version: 2 }] }),
    createPasskeySignedOperation: async (operation) => { calls.push(operation); return { accepted: true }; },
  },
});
await adapter.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: 'happy', sessionViewModel: session });
await adapter.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: 'angry', existingId: 'r', expectedPreviousRevision: 'rev', sessionViewModel: session });
await adapter.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: null, existingId: 'r', expectedPreviousRevision: 'rev2', sessionViewModel: session });
assert.deepEqual(calls.map((c) => c.action), ['forum.react', 'forum.edit', 'forum.delete']);
assert.equal(calls[0].parentId, 'p');
assert.equal(calls[1].entityId, 'r');
assert.equal(calls[1].expectedPreviousRevision, 'rev');
assert.deepEqual(calls[2].payload, { targetType: 'post', targetId: 'p' });
await assert.rejects(adapter.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: 'happy', sessionViewModel: { capabilities: {} } }));
assert.equal(calls.length, 3);
console.log('ok - reaction projection, attribution, escaping, signing and mutations');

let stale = [];
let revision = 0;
const paged = createForumDataAdapter({ relayBaseUrl: 'https://relay.example', appViewBaseUrl: 'https://view.example',
  fetchImpl: async () => new Response(JSON.stringify({ handle: 'alice' }), { status: 200 }),
  forumHostClient: {
    fetchForumHostInfo: async () => ({ canonical_base_url: 'https://relay.example' }),
    fetchHostedBoards: async () => ({ boards: [{ board_id: 1, title: 'Board', access_policy_version: 1 }] }),
    createPasskeySignedOperation: async () => ({ accepted: true, publication: { entity_id: 'saved-reaction', operation_id: `accepted-${++revision}` } }),
  },
  appViewClient: {
    fetchThreadFeed: async ({ cursor }) => cursor == null
      ? { items: content, has_more: true, next_cursor: 10 }
      : { items: stale, has_more: false },
  },
});
const loadReply = async () => (await paged.loadThreadPage({ boardId: '1', threadId: 't', sessionViewModel: session })).thread.posts[0];
await paged.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: 'happy', sessionViewModel: session });
assert.equal((await loadReply()).reactions[0].reactionType, 'happy');
stale = [reaction('saved-reaction', 'did:a', 'happy', 'insert', 'p', 11)];
await paged.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: 'angry', existingId: 'saved-reaction', expectedPreviousRevision: 'accepted-1', sessionViewModel: session });
assert.equal((await loadReply()).reactions[0].reactionType, 'angry');
await paged.submitReaction({ boardId: '1', targetType: 'post', targetId: 'p', reactionType: null, existingId: 'saved-reaction', expectedPreviousRevision: 'accepted-2', sessionViewModel: session });
assert.equal((await loadReply()).likeCount, 0);
console.log('ok - paginated attribution preserves accepted changes over indexing delay');
