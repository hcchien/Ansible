# Elix prod / TestFlight release — 2026-09-07

User authorized committing and pushing the completed S1–S5 / U1–U5 remediation and authority witness changes to prod, triggering CI/CD, and uploading the modified app to TestFlight.

## Constitution Review

The engineering constitution and compliance review were re-read. Publication retains user-held signing keys, explicit disclosure, and independently verified public authority. Deployment does not authorize blanket historical revalidation or account/key impersonation.

## Release scope

Prepared in a clean checkout from `a4bbaebb`, which matched origin/prod. The pre-remediation tracked diff was used as a three-way baseline to separate this task's changes. Existing government-credential integrations, platform bridge changes, unrelated federation edits, presentation assets, and local fixtures remain outside this release.

Signed archive and IPA built successfully; bundle ID, version, build number, distribution profile/team, codesign verification and compiled production endpoints checked. App source version: `1.0.10+2026090701`; production configuration from `config/production.json`. TestFlight upload is separate from App Store review submission.

AppView Cloud Build now configures `APPVIEW_PUBLIC_ORIGIN` for both the migration job and service. Migration jobs run with ingest off; services preserve the explicit `_START_INGEST` setting (default true). Both create/update job branches and the service update were verified using an isolated gcloud mock. Existing projections are not truncated during deployment. New uncheckpointed authority fails closed and requires client enrollment; existing historical projections are not automatically granted new witness receipts. Rebuild/owner revalidation requires the workflow described in the witness results.

## Local validation

- Clean-release AppView suite: 87 passed.
- Clean-release Relay suite: 491 passed.
- Clean-release Web suite: 130 successful outputs, exit 0.
- Complete Flutter static analysis: no issues.
- Focused remediation and production configuration gates: 86 passed (17 test files).
- Identity resolution contract and shell syntax checks passed.

The complete Flutter suite was additionally attempted against both the clean release and untouched prod baseline. Both produced the same 22 failing legacy UI tests, one skip, and stalled on the same home-shell sync tests. Both were interrupted after confirming identical failures; the complete Flutter suite is not claimed to pass. The focused security, identity, sync settings, Wallet and release-configuration gates are run separately to completion.

The comparison covers board-policy defaults, removed/moved home controls, thread view fixtures, notifications, moderation views, and home-shell sync/engagement tests. No failures unique to the release appeared before the shared stall. This bounded comparison is not a claim that all possible regressions are excluded.

Detailed local evidence is retained outside the commit under `/private/tmp/elix-release-*.log` and `/private/tmp/elix-baseline-flutter-tests.log`. Earlier validation and threat model: [remediation results](2026-09-07-elix-remediation-results.md), [authority witness results](2026-09-07-elix-authority-witness-results.md).
