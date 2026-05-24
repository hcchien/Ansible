# Repository Agent Instructions

These instructions apply to the entire repository.

## Constitution Gate

Before creating or updating any product spec, implementation plan, or feature
implementation that touches identity, storage, sync, verification, federation,
moderation, ranking, community governance, credentials, Wallet, Issuer, Relay,
Forum Host, or AppView behavior, agents MUST first read:

`docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`

Agents MUST treat that document as the highest product and engineering
constraint for Tris-Aura. If a requested change conflicts with the constitution,
the agent must stop, explain the conflict, and propose a constitution-compliant
alternative before editing implementation code.

When drafting or changing specs and implementation plans, include a
`Constitution Review` section or explicitly state why the constitution does not
apply.

## Current Known Gaps

Also check the current compliance review before claiming constitution
compliance:

`docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`
