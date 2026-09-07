# Elix S1–S5 / U1–U5 remediation

## Constitution Review

Read the engineering constitution and compliance review before implementation.
Preserve non-exportable identity custody, explicit distribution and disclosure,
optional verification, and historical authorship. Unknown verification evidence
fails closed. Neither host receipts nor a successful network request establish
author authority. Browser login keeps scoped, revocable app approval.

## Scope and acceptance

- S1: independently bind op keys to identity evidence and verify content-bound
  WebAuthn author authorization; reject forged receipts and projection mutations.
- S2: exclude the actual Android file-domain database and sidecars from both
  generations of backup rules and device transfer.
- S3/S4: cryptographic issuer/status verification, hardware holder signing,
  and consent bound to the exact credential/envelope and receiving origin.
- S5: scope recovery readiness to identity; distinguish generated and saved
  material without claiming that generating a blob proves recoverability.
- U1/U2: working public search/discovery and notification navigation; distinguish
  public boards and board policy from user subscriptions and posting authority.
- U3: same-device app handoff with validated login link and return destination.
- U4/U5: accurate privacy/permission copy and responsive accessible controls.

## Verification

Run relevant Dart/Flutter, frontend, Relay and AppView tests, including negative
security cases. Use an isolated local PostgreSQL test cluster rather than modify
the user's existing roles. Inspect local rendered frontend at mobile/desktop
sizes. Preserve all pre-existing dirty changes; no deployment is requested.

## Result and verification boundary

See `docs/reviews/2026-09-07-elix-remediation-results.md` for per-item implementation, test evidence, rollout order and remaining limits. Relay enforces present expiry/revocation for new submissions; AppView retains cryptographically valid historical authorship. A signed timestamp is not an independent time witness, and a served valid chain does not prove the absence of an undisclosed successor. Full malicious-source freshness protection is not claimed.
