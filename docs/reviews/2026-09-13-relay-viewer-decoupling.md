# Relay / Viewer decoupling — validation and release

## Constitution Review

Read the engineering constitution and compliance review. The user explicitly
selected Relay as the current-state and receipt-ordering source, retaining
independent author-signature, revocation and local rollback checks. Protection
against a malicious Relay withholding previously unseen updates is not claimed.
Private content and user identity key custody boundaries remain in place.

## Implementation

- Immutable did:key authors remain supported without inventing an anchor chain.
- New App no longer contacts AppView for checkpoints, anchor/recovery/veto,
  credential revocation, or local-history revalidation. Relay receipt completes
  publication independently of Viewer availability.
- Public deltas supply versioned minimal current authority status for each
  visible operation. Viewer derives verified state without App enrollment.
- Viewer independently checks signatures and author epochs using Relay receipt
  time, retains known revocations/frontiers and exact operation digests, and
  rejects forks, old-key backdating and tampered content.
- Existing pending records retry automatically with bounded persisted backoff;
  exact log identity/digest must match. Superseded projection hints prevent late
  retries from restoring obsolete edits/deletions. No full production rebuild.
- Legacy AppView authority endpoints remain for installed old clients; their
  existing state is preserved. New App makes no calls to them.
- Relay revocation retries preserve the earliest effective revocation time.

## Validation

- AppView: 95 tests passed, including independent Viewer bootstrap, historical
  keys, stale/unknown proof, revocation rollback and durable pending retry.
- Relay: 494 tests passed, including public status minimization and earliest
  revocation time. One test-helper call error was corrected before final pass.
- App: 43 related tests passed with an unavailable configured AppView.
- Targeted Flutter analyze: no issues. Identity resolution contract passes.
- Logs: /private/tmp/elix-viewer-appview-final-tests.log,
  /private/tmp/elix-viewer-relay-final-tests.log,
  /private/tmp/elix-viewer-app-tests.log,
  /private/tmp/elix-viewer-final-app-analyze.log.

## Release boundary

Prepared version 1.0.12 (2026091302). Production rollout, archive verification,
store upload and review replacement must each be verified independently.
Apple currently has 1.0.10 (2026090703) waiting for review. Google Play reported
an existing update published September 13; inspect its release before replacing.
Unrelated Wallet/Issuer changes in the user's original checkout are excluded.
