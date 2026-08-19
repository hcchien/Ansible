# Layered Identity & `did:elix` Method（Plan）

> Current custody terminology: this plan's early references to a single
> "backupable root key" describe the legacy/reduced-trust implementation.
> Hardware-capable clients now use purpose-separated, non-exportable device
> keys; encrypted identity recovery material does not contain a device hardware
> key, and recovery enrolls a new one. See
> [`did:elix` Method Rationale and Interoperability](../../architecture/did_elix_method.md).

> Status: **In implementation (v0.1)** — defines the canonical user identity
> method, the alias layer, the issuer trust model, and the cross-relay
> resolution protocol.
> Date: 2026-06-16
>
> **Owner decisions locked 2026-06-16:** migration = clean mint (D-MIG);
> scope this cycle = full Phases A–D; cross-relay resolution = build v0
> directly, no separate spec first (D-RES).
> Owners: identity, relay, core, wallet
>
> Builds directly on the self-certifying anchor chain from the
> [identity recovery & re-anchor design](2026-06-13-identity-recovery-reanchor-design.md)
> (Phase 1.0) — that chain is, in effect, the per-identity operation log
> this method resolves. Supersedes the assumption (today's code) that the
> canonical user DID is the `did:plc` local stub.

## Problem & Motivation

The repo is open source and explicitly wants **anyone to run their own
relay and frontend**. That single fact forces the identity decision:

- **`did:web` for users is wrong.** It ties identity to one operator's
  domain (`did:web:relay-a.com`), so a user cannot carry their identity to
  another relay without becoming a different identity — and the operator
  becomes the de-facto authority over user identity (violates Base Rule 1).
  `did:web` is correct only for **operator/org identity** (the issuer).
- **`did:key` for users is wrong for the *social/federation* role.** A
  `did:key` document is a pure function of the key: it cannot carry a
  `service` endpoint (where the user's data lives) or `alsoKnownAs` (the
  handle), and it cannot rotate the key without becoming a new identity
  (key compromise = permanent loss of followers/reputation/handle). It is,
  however, ideal for the **wallet / VC holder** role (universally
  resolvable, zero infra, and a verifier only needs the key to check a
  holder proof).
- **`did:plc` is the right *shape*** (domain-independent, portable,
  rotatable via an operation log) but the canonical method depends on
  Bluesky's `plc.directory`, which an independent open-source federation
  should not be captured by.

So no single DID method fits every role. The decision is to run **one
root key with role-specific DID representations**, cryptographically
linked, with exactly **one canonical** identity.

## The Model（一把根金鑰，多個角色表示）

```
                 root Ed25519 identity key
                 (backupable; recovery design Phase 1.0)
                          │
   ┌──────────────────────┼───────────────────────────┐
   ▼                      ▼                             ▼
did:elix:<id>        did:key:<mb>                  did:plc:<hash>
CANONICAL            wallet / VC holder            OPTIONAL atproto alias
social + federation  (universal verifier interop)  (minted only on opt-in
identity                                            Bluesky bridge)

   issuer / org identity is a different actor → did:web:issuer.<domain>
```

| Identifier | Role | Method | Canonical? | Resolves via |
|---|---|---|---|---|
| `did:elix:<id>` | Social / federation identity (the identity *itself*) | Ansible method (this doc) | **Yes — the only canonical** | Cross-relay resolution protocol over the anchor chain |
| `did:key:<mb>` | Wallet / VC holder (subject of credentials) | `did:key` | No — role alias | Deterministic (the key); no network |
| `did:plc:<hash>` | atproto / Bluesky face (opt-in) | `did:plc` | No — role alias | `plc.directory` (after opt-in publish) |
| `did:web:issuer.<domain>` | **Issuer** (org), not a user | `did:web` | n/a (different actor) | HTTPS `.well-known/did.json` |

**Binding rule.** `did:elix` and `did:key` share the **same root key** (a
`did:key` is just that key encoded — "free"). The optional `did:plc` is
bound by **bidirectional `alsoKnownAs` + shared/cross-signed key**. The
`did:elix` document's `alsoKnownAs` lists the handle, the `did:key`, and
(when bridged) the `did:plc`; one-directional claims are never trusted.

## `did:elix` Method（草案）

`did:elix` is the productization of the existing self-certifying anchor
chain — not a new trust mechanism, a *name and resolution layer* over one
we already designed and shipped the seed of.

- **Identifier:** `did:elix:<id>` where `<id>` is the content hash of the
  **genesis anchor object** (the `reason:"initial"` anchor). Stable,
  domain-independent, opaque — like a `did:plc` suffix, derived from our
  own genesis rather than `plc.directory`.
- **Operation log:** the hash-chained anchor objects
  (`io.trisaura.identity.anchor`, `prev_anchor_cid`) from the Phase 1.0
  design **are** the method's operation log. Rotation/recovery/device
  changes are already modeled there.
- **DID document (projected from the latest anchor):**
  - `verificationMethod` ← the current identity key (Ed25519);
  - `service` ← the user's current home relay/PDS endpoint (the property
    `did:key` cannot express);
  - `alsoKnownAs` ← `[ "at://<handle>", "<did:key>", optional "<did:plc>" ]`.
- **Self-certifying:** anyone can verify the chain from genesis without
  trusting the serving relay (already true of the anchor chain). The
  resolver returns *evidence*, not *authority*.

This means **most of `did:elix` already exists** — the new work is (1) the
identifier derivation + DID-document projection, (2) swapping the canonical
from the `did:plc` stub to `did:elix`, and (3) the cross-relay resolution
protocol.

## Cross-Relay Resolution Protocol（最核心、最新的設計工作）

The anchor chain already gives **identity portability** (carry your keys +
chain, re-anchor at any relay — recovery design §Relay portability). What
is missing is **resolution portability**: a third party, given
`did:elix:xxx`, finding the *current* DID document (keys + home relay +
handle) when they don't already know which relay hosts it.

Design constraints (from the open-source, multi-operator goal):

- **No single authority.** It must not become one central directory whose
  operator can forge or withhold identity (that would re-introduce the
  Base Rule 1 problem `did:web` had).
- **Answers are verifiable.** Because anchors are self-certifying, a
  resolver's answer can be checked locally regardless of *who* served it —
  so the directory can be "trusted but verifiable," like `did:plc`'s log,
  without being a chokepoint.

Scope is staged (full open-membership directory governance is its own
spec — see Non-Goals):

- **v0 (this plan): federated lookup over a known relay set.** Each relay
  serves resolution for the `did:elix` it anchors and replicates a
  lightweight `(did:elix → home-relay hint, latest-anchor-cid)` index to
  peer relays it federates with. A resolver asks any relay in its
  configured set; the returned anchor chain is verified locally. This
  covers "users on relays that federate with each other resolve each
  other."
- **Later (own spec): open discovery + governance.** Global resolution for
  relays *not* in your set (gossip/DHT/shared verifiable log),
  anti-squat/anti-Sybil for the index, and handle-uniqueness across the
  federation. Decision D-RES below.

## Issuer Trust Model（VC：issuer = did:web + Trust Registry）

Already-correct in the [VC wallet spec](../../protocol/tris_aura_vc_wallet_spec_v0.1.md):
issuer is `did:web:issuer.<domain>`, holder is `did:key`. This plan adds
the missing piece that an "anyone can run an issuer" world requires:

- **Why `did:web` for the issuer (not `did:key`):** accepting a credential
  is a decision about **who issued it and whether you trust them** — a
  real-world accountability question. `did:web` anchors the issuer to a
  **nameable, evaluable domain/org** you can put on a trust list; a
  `did:key` issuer is an opaque key you cannot govern.
- **`did:web` is necessary but not sufficient.** Anyone can buy a domain.
  The real accept/reject gate is a **Trust Registry**: a signed list of
  accepted `(issuer did:web, credential type, assurance level)` entries.
  A default registry ships with the app/relay; relays and users can
  override (add/remove issuers). This is how real VC ecosystems work
  (cf. EBSI Trusted Issuers Registry).
- **Holder stays `did:key`** because the holder is *not* who you decide to
  trust — you only verify the holder controls the subject. `did:key` gives
  universal verifier interop (TW gov / OID4VP verifiers resolve it with no
  infra). The cost — key rotation orphans credentials — is handled as an
  **explicit product event** (see D-ROT): device loss restores the *same*
  key (credentials survive); key *compromise* requires re-issuance, which
  is the normal security flow, not a silent breakage.

## Constitution Review

Per [AGENTS.md](../../../AGENTS.md), this touches identity, credentials,
federation, and trust. Checklist:

1. **Identity/credentials involved:** the user's canonical identity method,
   the wallet holder identifier, the optional atproto alias, and the issuer
   trust list. This plan *strengthens* identity autonomy — it removes the
   `did:plc`-stub / domain-bound options that would have made an operator
   the authority.
2. **Data leaving the device:** no new private data path. The DID document,
   anchor chain, and `alsoKnownAs` aliases are already-public,
   self-certifying objects. The opt-in `did:plc` bridge publishes only a
   public DID operation to `plc.directory`, and **only on explicit user
   action** (Base Rule 2: opt-in, never default).
3. **Minimum claim:** unchanged. Resolution returns identity-continuity
   evidence (keys, endpoint, handle), no personhood or legal-identity data.
4. **Raw legal identity:** never present in DID documents, the directory,
   or the trust registry. The trust registry holds issuer domains +
   credential types, not subjects.
5. **Trust/ranking change:** the Trust Registry becomes a reason-coded
   policy input (which issuers are accepted) — per Base Rules 4/7, with an
   explicit default + user/relay override, no silent allow-listing.
6. **Personhood bindings:** unchanged. Holder `did:key` is the credential
   subject exactly as today; nullifier/duplicate-prevention untouched.
7. **Exit/rotation:** this plan *is* exit-strengthening. `did:elix` is
   domain-independent and portable across relays; the resolution protocol
   is explicitly designed **not** to have a single authority; key rotation
   keeps the same `did:elix` via the anchor chain. The `did:key` rotation
   limitation for credentials is documented as an explicit event (D-ROT),
   not hidden.
8. **External hosts:** any relay can resolve and verify a `did:elix`
   independently (self-certifying chain). Accepting a `did:plc` bridge or a
   given issuer is each host's policy, expressed via the trust registry —
   no host must trust our relay's word.

**Verdict:** compliant, and net-positive for Base Rule 1. Mandatory
elements carried into implementation: (a) the resolution protocol must
have no single forge-or-withhold authority — answers stay
locally-verifiable; (b) the `did:plc` bridge is strictly opt-in; (c) the
trust registry ships with an explicit, inspectable default and a user/
relay override; (d) the `did:key` credential-rotation event is surfaced in
the recovery/security UX, never silent.

## Decisions（待決事項）

| # | Decision | Default position |
|---|---|---|
| D-CANON | Canonical user method | **`did:elix`** (this doc). `did:plc` demoted to opt-in alias; `did:web` reserved for issuer/org; `did:key` is the wallet role alias of the same root key |
| D-MIG | Migrating today's `did:plc`-stub canonical to `did:elix` | **LOCKED 2026-06-16 → clean mint.** Pre-launch, near-zero real users → mint `did:elix` as canonical from the root key + genesis anchor; no historical migration. Existing dev accounts (incl. `hcchien`) re-mint fresh; old `did:plc`-stub strings / handle bindings / op authorship are treated as disposable |
| D-RES | Cross-relay resolution mechanism beyond a known relay set | **LOCKED 2026-06-16 → build v0 directly** (no separate spec first): federated lookup + replicated verifiable index over a configured relay set. Global open-membership directory (gossip/DHT/shared log) + anti-squat governance still a follow-up spec |
| D-ROT | `did:key` holder credential survival across key change | Device loss → restore same key → credentials survive. Key **compromise** → new `did:key` → **re-issue credentials** (explicit security event in recovery UX). Do not pretend `did:key` rotates losslessly |
| D-PLC | Real `did:plc` for the bridge | Replace the `did_plc.rs` JSON-hash stub with spec-compliant DAG-CBOR genesis (the existing `cid.rs`/`lexicon.rs` DAG-CBOR is the building block); publish to `plc.directory` only on opt-in |
| D-TR | Trust Registry distribution | Signed default list shipped in-repo + fetched/cached; relay and user overrides. Start static, add fetch/rotation later |

## Phased Implementation（分階段）

Ordered so the canonical swap and the wallet/issuer clarity (cheap, mostly
already-built) land first, and the genuinely new resolution protocol is its
own phase. Each phase keeps a Constitution Review when it gets its own
sub-plan, per the AGENTS.md gate.

### Implementation status (2026-06-16)

| Phase | Status |
|---|---|
| A — store/core foundation | ✅ done + tested (37 store tests; `did:key` encoder cross-verified vs rust `bs58`) |
| A — relay (`did:elix` canonical, `also_known_as`, DID-document resolution, `validate_did`) | ✅ done + tested (full relay suite 317 green) |
| A — **app registration → `did:elix` + `main.dart` persistence** | ⏳ deferred to a runtime-testable on-device pass (touches the boot/identity path) |
| B — Issuer Trust Registry | ✅ done + tested (`:untrusted_issuer` reason, per-issuer credential-type gating; app `VcVerifier` already aligned) |
| C — cross-relay resolution v0 | ✅ done + tested (Elixir `DidElix` cross-matched to Dart; `FederatedResolver` local-first + self-certifying peer verification; app `DidElixResolver`; lying-peer rejection proven). **v0 limit:** self-cert proves the genesis binding, so peer-resolving a *rotated* identity needs the full chain — documented follow-up |
| D — opt-in Bluesky bridge (real `did:plc`) | ⏳ scoped below — not started |

### Phase A — `did:elix` canonical + alias binding （core/app/relay）

1. **(rust/core)** `did:elix` identifier derivation from the genesis anchor
   CID; DID-document projection from the latest anchor (verificationMethod
   + `service` endpoint + `alsoKnownAs`). Reuse existing `cid.rs` /
   anchor-chain code.
2. **(app/did)** Derive `did:key` from the same root identity key; write
   `also_known_as` (`at://handle`, `did:key`, optional `did:plc`) into the
   anchor object (`schema_version` bump + lazy migration per the recovery
   design's migration section).
3. **(app)** Swap the canonical from the `did:plc` stub to `did:elix` in
   `main.dart` (`_anchoredDid`/`_loadPersistedIdentity`); the wallet
   `holderDid` becomes the `did:key` (it is already `did:key` in the VC
   spec — wire the app to pass the `did:key` form explicitly).
4. **(relay)** Anchor store + `did_accounts` cache keyed by `did:elix`;
   `resolveHandle`/resolution returns the projected DID document; keep the
   self-certifying chain authoritative over the cache.

Exit: a new account is `did:elix:…` canonical with a linked `did:key`;
relay resolves handle → `did:elix` DID document; existing dev accounts
migrate on next launch with no manual DB edits.

### Phase B — Issuer Trust Registry + holder clarity （issuer/relay/app）

1. Trust Registry format: signed list of `(issuer did:web, credential
   type, assurance level)`; in-repo default + override hooks.
2. VP verification (relay VP verifier + app verifier) consults the
   registry before accepting a credential; reason-coded rejection
   (`untrusted_issuer`).
3. Document/confirm holder = `did:key` end-to-end (already true in the
   spec); add the D-ROT credential-rotation event to the recovery/security
   UX copy.

Exit: a VP from an issuer not in the registry is rejected with a clear
reason; the default registry is inspectable; holder proofs verify against
`did:key` with no infra.

### Phase C — Cross-relay resolution protocol v0 （relay/app）

1. Relay publishes "I anchor `did:elix:xxx`" + replicates a lightweight
   verifiable index `(did:elix → home hint, latest-anchor-cid)` to
   federated peer relays.
2. Resolution endpoint: given `did:elix`, return the anchor chain / DID
   document (locally, or via a federated peer); caller verifies the chain.
3. App resolver: resolve `did:elix` across a configured relay set and
   verify locally; cache with the anchor CID as the validator.

Exit: a user on relay A can be resolved+verified by a client talking to
relay B when A and B federate, without B trusting A's word.

### Phase D — Opt-in Bluesky bridge （core/relay/app）

> **Correctness gate (must hold before shipping):** real `did:plc` requires
> **canonical DAG-CBOR** map-key ordering (length-then-bytewise per DAG-CBOR,
> NOT the alphabetical `BTreeMap` the current stub uses) and the DID =
> `did:plc:` + base32-lower(sha256(dag-cbor(signed genesis)))[0..24]. `ciborium`
> is already a rust-core dep, but ciborium does **not** auto-canonicalize key
> order — the op map must be ordered explicitly. This MUST be locked against a
> **real plc.directory test vector** before use, or we mint DIDs the live
> directory rejects (defeating the bridge). Network publish + FRB codegen to
> expose it to the app also land here. This is why D is sequenced last and is
> explicitly opt-in / post-launch.

1. **(rust/core)** Replace the `did_plc.rs` JSON-hash stub with
   spec-compliant DAG-CBOR `did:plc` genesis (D-PLC): canonical key ordering,
   Ed25519 sig as base64url-nopad, DID from sha256(dag-cbor) base32 truncated to
   24 chars; cargo test against a published plc.directory vector.
2. Bridge flow: on explicit opt-in, mint the `did:plc`, bind via
   `alsoKnownAs` + shared key into the `did:elix` anchor, publish the
   genesis op to `plc.directory`; canonical stays `did:elix`.
3. UX: a clear "connect to Bluesky" affordance stating what is published.

Exit: a user who opts in has a resolvable `did:plc` on `plc.directory`
linked to their `did:elix`; users who don't opt in publish nothing
external. **Content interop (repo sync / firehose / `app.bsky.*`
lexicons) is explicitly out of scope here** — identity bridge only.

## Non-Goals（本計畫不含）

- Global open-membership directory governance, anti-squat/anti-Sybil for
  the resolution index, and federation-wide handle uniqueness — **own
  follow-up spec** (D-RES "Later").
- atproto **content** interoperability (MST/CAR repo sync,
  `com.atproto.sync` firehose, `app.bsky.*` lexicons) — separate from the
  identity bridge in Phase D.
- Hardware key custody (still deferred per the recovery design D1).
- Migrating credential subjects off `did:key` (the rotation trade-off is
  accepted and handled by D-ROT, not by changing the holder method).

## Doc Updates This Plan Implies（連動文件）

- [Federation strategy](../../protocol/tris_aura_federation_strategy_v0.1.md)
  Identity Model — `did:elix` as canonical, resolution layer, `did:plc`
  reframed as opt-in alias (done with this plan).
- [VC wallet spec](../../protocol/tris_aura_vc_wallet_spec_v0.1.md) — add
  the Issuer Trust Registry section + holder=`did:key` rationale (done).
- [Service architecture plan](../../architecture/service_architecture_plan.md)
  — new gaps + a phase for the `did:elix` method and cross-relay resolution
  (done).
- [ROADMAP](../../ROADMAP.md) — add the identity-method workstream; the
  AT Protocol "Freeze" line becomes "opt-in `did:plc` bridge" (done).
- [Recovery design](2026-06-13-identity-recovery-reanchor-design.md) — note
  that the anchor `did` is now `did:elix` and the chain is the `did:elix`
  operation log (done).
