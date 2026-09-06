import assert from 'node:assert/strict';
import { buildThreadsFromFeed } from '../src/forum_data_adapter.mjs';
const thread = (id, created_at, log_id) => ({ entity_type: 'thread', op_type: 'insert', entity_id: id, created_at, log_id, payload: { title: id } });
const feed = [thread('old', '2026-09-01T00:00:00Z', 1), thread('new', '2026-09-02T00:00:00Z', 2),
  { entity_type: 'thread', op_type: 'update', entity_id: 'old', created_at: '2026-09-06T00:00:00Z', log_id: 3, payload: { title: 'edited' } }];
assert.deepEqual(buildThreadsFromFeed(feed).map(t => t.id), ['new', 'old']);
feed.push({ entity_type: 'post', op_type: 'insert', entity_id: 'reply', created_at: '2026-09-03T00:00:00Z', log_id: 4, payload: { threadId: 'old', content: 'Reply' } });
const result = buildThreadsFromFeed(feed);
assert.deepEqual(result.map(t => t.id), ['old', 'new']);
assert.equal(result[0].createdAt, '2026-09-01T00:00:00Z');
assert.equal(result[0].lastActivityAt, '2026-09-03T00:00:00Z');
console.log('ok - discussion order follows reply publication, not edits');
