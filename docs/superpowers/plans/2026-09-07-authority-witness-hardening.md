# Independent authority observation for S1

## Constitution Review

Read constitution and current compliance review. Identity signatures remain the
source of author authority; this AppView is a separately contacted observer of
ordering, not an identity-key custodian. Store public authority chains,
revocation identifiers and operation digests only. Do not move private data or
credentials to the observer. Preserve historically observed signed operations;
reject unobserved operations signed by an authority that is no longer current.
No sole-operator claim: protection assumes this configured AppView and its
persistent witness database are honest. A malicious Relay cannot alter it.
Multiple malicious/colluding observers and pre-enrollment hidden history are
outside that claim. A new observer must not silently assert it witnessed history.

## Implementation

- Persistent, transactional per-DID authority frontier and irreversible signed
  credential revocations, separate from disposable feed projections.
- App calls the configured AppView directly when publishing identity anchors
  or revoking web credentials. Success requires observer acknowledgement;
  Relay cannot substitute its own claimed acknowledgement.
- First observation verifies against the observer's current key and current
  delegation status/time, regardless of author-supplied timestamps.
- Save an immutable digest and verified authority snapshot for each op id.
  Exact observed history can replay after expiry/rotation/revocation and after
  projection rebuild. Different bytes under an observed op id fail closed.
- Unknown authority, stale/forked chains, missing observation for obsolete keys,
  and expired/revoked delegations produce explicit verification failures.
- Serialise checkpoints/revocations/operation observations under the same DID
  database lock so a raced revocation has a single defined ordering.
- No mass grandfathering of old Relay data. Existing histories without witness
  evidence require an explicit migration/owner-authorized revalidation workflow;
  preserve source data and report pending verification rather than manufacture
  first-seen timestamps.

## Tests

Cryptographic signed fixtures, old-key backdating, withheld revocation, expiry,
conflicting operation replay, state rollback/forks, root-signature rejection,
historical replay after status changes and rebuild, transaction races, and
native direct-to-observer URL/error propagation. Use isolated local PostgreSQL.

## Completion

Implemented and locally verified. See [results and rollout requirements](../../reviews/2026-09-07-elix-authority-witness-results.md): AppView 87, Relay 491, Flutter 78 tests passed; touched native analysis clean. No commit/deployment.
