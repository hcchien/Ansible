import assert from 'node:assert/strict';

import {
  CONTRACT_FIXTURES,
  createFixtureForumHostClient,
  createFixtureStorage,
  createFixtureWebSessionClient,
} from '../src/contract_fixtures.mjs';
import { ERROR_TYPES } from '../src/error_taxonomy.mjs';
import { WEB_SESSION_TOKEN_KEY } from '../src/web_session_client.mjs';

assert.equal(CONTRACT_FIXTURES.sessions.anonymous.trust_tier, 'anonymous');
assert.equal(
  CONTRACT_FIXTURES.sessions.approvedDid.trust_tier,
  'self_custody_did',
);
assert.equal(CONTRACT_FIXTURES.challenge.pending.status, 'pending');
assert.equal(CONTRACT_FIXTURES.challenge.approved.session_token, undefined);
assert.equal(CONTRACT_FIXTURES.sessions.approvedDid.session_id, 'wsi_fixture');
assert.equal(CONTRACT_FIXTURES.errors.missingScope.type, ERROR_TYPES.missingScope);
assert.equal(CONTRACT_FIXTURES.errors.rateLimited.type, ERROR_TYPES.rateLimited);
assert.equal(CONTRACT_FIXTURES.forum.host.forum_host_id, 'host-local-dev');
assert.equal(CONTRACT_FIXTURES.forum.boards[0].hosted_board_id, 'general');
assert.equal(CONTRACT_FIXTURES.forum.threadAccepted.accepted, true);
console.log('ok - exposes stable frontend contract fixtures');

const storage = createFixtureStorage({ token: 'wst_fixture' });
assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), 'wst_fixture');
storage.removeItem(WEB_SESSION_TOKEN_KEY);
assert.equal(storage.getItem(WEB_SESSION_TOKEN_KEY), null);
console.log('ok - creates localStorage-compatible fixture storage');

const webSessionClient = createFixtureWebSessionClient();
const challenge = await webSessionClient.createWebSessionChallenge();
assert.equal(challenge.challenge_id, 'wsc_fixture');
assert.deepEqual(await webSessionClient.fetchChallengeStatus(), CONTRACT_FIXTURES.challenge.approved);
assert.deepEqual(await webSessionClient.fetchCurrentWebSession(), CONTRACT_FIXTURES.sessions.approvedDid);
console.log('ok - creates fixture web session client');

assert.equal(CONTRACT_FIXTURES.moderation.report.reason_code, 'spam');
assert.equal(CONTRACT_FIXTURES.moderation.openReports.length, 3);
assert.equal(
  CONTRACT_FIXTURES.errors.notBoardModerator.type,
  ERROR_TYPES.notBoardModerator,
);
assert.equal(CONTRACT_FIXTURES.errors.invalidReasonCode.status, 422);
assert.equal(CONTRACT_FIXTURES.errors.unknownTarget.status, 422);
assert.deepEqual(CONTRACT_FIXTURES.moderation.boardState.locked_threads, [
  { thread_id: 'thread-9', reason_code: 'harassment' },
]);
console.log('ok - exposes moderation contract fixtures');

const moderatorClient = createFixtureForumHostClient();
assert.deepEqual(await moderatorClient.fetchWebModerationReports(), {
  reports: CONTRACT_FIXTURES.moderation.openReports,
});
assert.deepEqual(await moderatorClient.fetchWebModerationActions(), {
  actions: CONTRACT_FIXTURES.moderation.auditActions,
});
assert.deepEqual(await moderatorClient.fetchBoardModerationState({ boardId: 'general' }), CONTRACT_FIXTURES.moderation.boardState);
assert.deepEqual(
  await moderatorClient.fetchBoardModerationState({ boardId: 'other' }),
  CONTRACT_FIXTURES.moderation.emptyBoardState,
);

const nonModeratorClient = createFixtureForumHostClient({ moderator: false });
await assert.rejects(
  () => nonModeratorClient.fetchWebModerationReports(),
  (error) => {
    assert.equal(error.status, 403);
    assert.equal(error.code, 'not_board_moderator');
    return true;
  },
);
console.log('ok - fixture forum host client enforces the moderator gate');

const forumHostClient = createFixtureForumHostClient();
assert.deepEqual(await forumHostClient.fetchForumHostInfo(), CONTRACT_FIXTURES.forum.host);
assert.deepEqual(await forumHostClient.fetchHostedBoards(), {
  boards: CONTRACT_FIXTURES.forum.boards,
});
assert.deepEqual(
  await forumHostClient.createHostedWebThread({ title: 'Fixture thread' }),
  CONTRACT_FIXTURES.forum.threadAccepted,
);
console.log('ok - creates fixture forum host client');
