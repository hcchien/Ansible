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

## Production verification

- Remote prod includes a4940ab949c61ebdbe237725c12ad951b7cfb301 and
  93bfc649e9dd98657c9cd55f030d311910b8f53a. Both Relay/AppView pipelines succeeded.
- Latest AppView build: 8ab62598-db4a-4ed4-867d-4ecc2250deed;
  revision ansible-appview-prod-00015-hmw receives 100% traffic.
- Latest Relay build: 14faf9e4-4a8e-4158-a4d8-68109af12b70;
  revision ansible-relay-prod-00038-q75 receives 100% traffic.
- Production Relay log 160 exposes active minimal authority status. The previously
  pending public entity 289a8bb5-af36-401b-8d80-fe0e17e4a841 is now returned by
  AppView, retaining created_at 2026-09-12T15:05:20.314456Z. No re-post or
  production projection reset was performed.

## Release verification

- Version 1.0.12 (2026091302), production endpoints, com.reviz.elix.
- iOS archive codesign/provisioning verified; upload succeeded at 20:26 on
  September 13. Apple processing complete; build
  4531623f-d256-40eb-bd18-e4854138b1c1 assigned to internal Elix group (3 testers).
- Apple 1.0.10 review cancelled. 1.0.12 with build 2026091302 submitted and
  reopened as Waiting for Review. All 12 existing release-note locales updated
  and read back; existing screenshots, optional identity flow, review contact,
  automatic release and rating settings preserved.
- Android release AAB signed with Elix Upload certificate; jar verification
  succeeds. Version/package, production URLs and three ABIs checked. Both
  binaries omit the removed AppView checkpoint write endpoint.
- Android packaging initially used Homebrew rustc despite installed rustup
  targets. Prepending /Users/hcchien/.cargo/bin resolved the toolchain mismatch.
- AAB SHA256: 4255cb9ea209e8e5f7b89222b4eb32a6f35b8b5607331ff5704e9af993ace2ba.
- Google Play 1.0.10 (2026090703) was already live on September 13. 1.0.12 is
  submitted as the next production update, with 12 localized release notes,
  unchanged supported devices and the existing countries/100% rollout setting.
  Publishing overview confirms Changes in review for 1.0.12 (2026091302);
  automated pre-review checks are still running. Approval/public availability
  is not claimed.
- Unrelated Wallet/Issuer changes in the user's original checkout are excluded.
