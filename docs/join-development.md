# Join Development

Welcome. This guide is the starting point for contributors to Elix / Tris-Aura.
It explains how to choose a first task, find the right service, and make a
change without weakening the project's local-first and minimal-disclosure
guarantees.

## Start Here

1. Read the root [README](../README.md) for the product and service map.
2. Follow [Developer Onboarding](getting-started-dev.md) to install toolchains,
   generate bindings, and run the app plus Relay locally.
3. Read the component README before changing its code.
4. Check [ROADMAP](ROADMAP.md) and the relevant architecture document before
   choosing work that spans services.

For a small first contribution, prefer a focused test, documentation correction,
accessibility/localization improvement, or a bug confined to one component.
Avoid combining a UI change, protocol change, and data migration in the same
first patch.

## Service Map

| Area | Start directory | Use it for |
|---|---|---|
| App and Wallet | `ansible_node/app` | Flutter UI, local-first flows, credential presentation consent |
| Domain and storage | `ansible_core/` | Shared Dart domain rules and Drift SQLite storage |
| Cryptographic core | `ansible_rust_core/` | DID, signing, FFI-backed protocol primitives |
| Relay / Forum Host | `ansible_relay/phoenix` | Signed ops, discovery, hosted boards, reputation, web sessions |
| AppView | `ansible_appview/phoenix` | Read-model projections, feeds, discovery/search |
| Credential Issuer | `ansible_issuer/go` | VC issuance, provider integrations, credential status/revocation |
| Passport proof verifier | `ansible_zkpassport_verifier` | Pinned ZKPassport proof verification only; it never issues credentials |
| Web frontend | `ansible_distribution_frontend` | Public Forum Host views and app-approved web sessions |

The architecture overview is in
[full_system_architecture.html](architecture/full_system_architecture.html) and
the service evolution plan is in
[service_architecture_plan.md](architecture/service_architecture_plan.md).

## Pick Work Safely

Before starting, search for an existing spec, plan, test, or implementation
that owns the behaviour. Keep the change in that boundary unless the task is
explicitly cross-service.

Changes involving any of the following require the constitution gate before
implementation: identity, Wallet, credentials, storage, sync, verification,
federation, moderation, ranking, community governance, Relay, Forum Host,
Issuer, or AppView.

Read both documents and include a `Constitution Review` section in a new or
changed spec/plan:

- [Engineering Constitution](superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md)
- [Current Compliance Review](superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md)

The important default is simple: raw legal identity, passport/chip data,
provider assertions, biometrics, private keys, and private content must not
enter public credentials, Relay/AppView payloads, normal logs, or federation.
When unsure, stop at the boundary and ask for a design decision rather than
adding a fallback.

## Local Development Loop

Use the smallest relevant loop first. The full commands and database setup are
in [Developer Onboarding](getting-started-dev.md).

```bash
# List supported workflows.
make help

# Run all suites when your environment supports every toolchain.
make test

# Re-generate Rust↔Dart bindings after Rust FFI API or Drift schema changes.
./setup_codegen.sh
```

Typical focused checks:

```bash
cd ansible_node/app && flutter test
cd ansible_rust_core && cargo test
cd ansible_relay/phoenix && MIX_ENV=test mix test
cd ansible_appview/phoenix && MIX_ENV=test mix test
cd ansible_issuer/go && go test ./...
cd ansible_zkpassport_verifier && pnpm test
```

Run only checks that cover your patch while iterating, then run the broader
relevant suite before handoff. State any toolchain or environment limitation
plainly; do not replace a failed security-sensitive test with an unverified
claim.

## Passport NFC / ZKPassport Work

Passport NFC is optional and currently `Beta`. The authoritative design is
[Embedded ZKPassport Issuance Design](superpowers/specs/2026-07-23-embedded-zkpassport-issuance-design.md).

- Raw passport material stays on the device.
- The Go Issuer owns challenges, duplicate-binding policy, and VC issuance.
- `ansible_zkpassport_verifier` verifies pinned proofs and public inputs, but
  cannot issue a credential.
- Unknown/mismatched proof material, bad holder or challenge bindings, replay,
  expiry, unavailable verification, and duplicate active bindings must fail
  closed.
- Production requires IAM-only Cloud Run invocation by the Issuer service
  account. The current generic verifier deployment exception is a documented
  production blocker; do not treat it as an approved deployment pattern.

The retired Relay Phase-1 Groth16 anchor flow and its
`ZkpVerificationKeys` configuration are not the current Passport NFC verifier.

## Before You Hand Off a Change

- Keep the patch focused and do not overwrite unrelated local work.
- Add or update tests for behaviour changes; update the relevant architecture,
  spec, or runbook when the system boundary changes.
- Run formatting and targeted tests; report exactly what you ran and what was
  not runnable.
- Explain user-visible, security, storage, and migration effects in the change
  description.
- Never commit secrets, production credentials, raw identity data, or generated
  local build output.

If the work changes a public API, storage schema, signing format, credential
claim, or privacy boundary, ask for review before treating it as a routine
implementation task.
