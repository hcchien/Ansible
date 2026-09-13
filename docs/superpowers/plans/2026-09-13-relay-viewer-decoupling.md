# Relay API and independently consuming Viewers

## Constitution Review

Read the engineering constitution and compliance review. Identity remains
self-certifying and user signed; private data remains outside public deltas.
The user explicitly chose the configured Relay as the source for current-state
completeness and receipt ordering. This supersedes the Sept 7 requirement for
App-to-AppView independent checkpoints. We do NOT claim resistance to a Relay
that hides previously unseen updates or falsifies receipt times. Known signed
rotations, revocations and operation digests cannot be rolled back locally.
No full constitution-compliance claim is made.

## Contract

- App registration, anchor/recovery/veto, enrollment and web revocation contact
  Relay only. Remove AppView checkpoint/revalidation actions from the new app.
- Public Relay deltas attach versioned current authority status, including
  public anchor chain and only the credential status needed by that public
  operation. No account credential listing, private claims or keys are exposed.
- Only the configured Relay ingest path activates Relay-state verification.
  Viewer verifies author and WebAuthn signatures independently, checks receipt
  time against key/delegation/revocation epochs, rejects forks/rollback, and
  persists immutable operation observations plus known revocations.
- New Viewers derive indexes from the same Relay evidence without author
  enrollment. Previously observed history remains replayable. Missing or invalid
  proof never becomes a blanket unsigned/legacy exemption.
- Keep old AppView authority HTTP endpoints during old-client migration; new
  clients make no writes to them. Existing security state is preserved.
- Bounded durable retries fetch exact pending log identifiers, match the original
  digest and re-fold with current Relay status. Retry metadata survives restarts;
  no production-wide projection reset is required.

## Verification and release

Tests cover Viewer outage during App sync, no Viewer writes in identity flows,
independent Viewer bootstrap, tampering, obsolete keys with backdated payloads,
revoked and historical web operations, local rollback/fork protection, delayed
proof and restart-safe retry. Verify production Relay and AppView rollout before
building the latest app, then verify signed production endpoints and store
processing before replacing pending review versions. Preserve unrelated work.
