# Product flow remediation

Status: local implementation complete; deployment and device validation pending. Base: a846fb40 (production 1.0.12).

Implementation evidence and outstanding release checks: [report](../../reviews/2026-09-14-product-flow-implementation.md).

## Scope and acceptance

- PD1: exact public content routes from discovery, search and shares; public reading does not require a subscription; protected content remains gated.
- PD2: distinguish local persistence, pending authorization, queued delivery, acceptance and failure; durable retry and sanitized diagnostics using existing operation identities.
- PD3: account/target-scoped local composer drafts for discussion, polls, replies and murmurs, restored without signing or publication.
- PD4: truthful onboarding and separate explanations for author signatures and verified-human qualifications.
- PD5: normal public browsing before identity creation, with an explicit transition to registration for interaction.
- PD6: Following does not silently include Explore; local search is explicitly separate from network search.
- PD7: recovery navigation distinguishes old-device approval, lost-device recovery, browser authorization and content backup limitations.
- PD8: native social reads use Relay-owned public query APIs, with no AppView proxy or checkpoint confirmation dependency. AppView remains an independent Web consumer.

## Constitution Review

The engineering constitution and current compliance review were read before implementation. Drafts remain local and account scoped. Restoring a draft never signs or distributes it. Private and protected content must not enter anonymous read/search results. Existing author proofs, credential revocations and rollback checks remain intact. Relay is the selected availability and latest-state source; no claim is made that a Viewer can detect a malicious Relay withholding newer state. Public search only transmits a query when the user chooses public search. Diagnostics exclude content, credentials, tokens and private keys. No new personhood binding or trust-tier promotion is introduced. Existing host compliance and hardware-custody gaps are not declared solved by this work.

## Verification

Use isolated worktree and test databases. Add behavior tests for privacy filtering, pagination, exact content routing, draft restoration/isolation and truthful delivery/scope states. Run affected Flutter, Relay and Web suites and static analysis. Record test results and any device-only limitations before marking review items complete. Store submission and deployment are separate from local verification.
