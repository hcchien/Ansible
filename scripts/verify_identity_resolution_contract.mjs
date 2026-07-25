import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../contracts/identity-resolution/v1/', import.meta.url);
const rules = await json('rules.json');
const boardSchema = await json('board.schema.json');
const authorSchema = await json('public-author.schema.json');
const boardCases = await json('conformance/board-resolution.json');
const authorCases = await json('conformance/public-author-resolution.json');

assert.equal(rules.version, 1);
assert.deepEqual(rules.board_match_fields, ['id', 'slug', 'legacy_ids']);
assert.deepEqual(rules.public_author_priority, ['handle', 'abbreviated_did']);
assert.equal(rules.anonymous_only_when_public_identity_missing, true);
assert.deepEqual(boardSchema.required, ['id', 'slug', 'legacy_ids']);
assert.deepEqual(authorSchema.required, ['did']);

for (const testCase of boardCases) {
  assert.equal(typeof testCase.name, 'string');
  assert.equal(typeof testCase.reference, 'string');
  assert.ok(Array.isArray(testCase.boards));

  for (const board of testCase.boards) {
    assert.equal(typeof board.id, 'string');
    assert.equal(typeof board.slug, 'string');
    assert.ok(Array.isArray(board.legacy_ids));
  }

  const requested = testCase.reference.trim();
  const match = requested
    ? testCase.boards.find((board) =>
        [board.id, board.slug, ...board.legacy_ids].includes(requested),
      )
    : null;
  assert.equal(match?.id ?? null, testCase.expected_id, testCase.name);
}

for (const testCase of authorCases) {
  const { did, handle } = testCase.author;
  const cleanDid = String(did ?? '').trim();
  const cleanHandle = String(handle ?? '').trim();
  const label = cleanHandle ||
    (!cleanDid
      ? 'anonymous'
      : cleanDid.length <= 16
        ? cleanDid
        : `${cleanDid.slice(0, 7)}...${cleanDid.slice(-6)}`);
  assert.equal(label, testCase.expected, testCase.name);
}

console.log('identity resolution contract verified');

async function json(path) {
  return JSON.parse(await readFile(new URL(path, root), 'utf8'));
}
