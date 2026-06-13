# Identity Recovery & Re-Anchor Design（Phase 1.0）

> Status: **Design for review** — settles architecture decisions D1 and D5
> and the anchor-portability half of G15. Gates Phase 1 hardware-key
> custody (G1/G14) and should be agreed before Phase 2 freezes the
> ops/snapshot schema. See
> `docs/architecture/service_architecture_plan.md`.
> Date: 2026-06-13

**Problem.** Phase 1 moves signing keys into platform secure hardware,
which makes them unexportable *by design*. Today the only copy of a user's
Ed25519 identity key is raw hex in `flutter_secure_storage`
(`ansible_core/did/`): lose the device, lose the identity — and the relay
anchor (`did_accounts` row: did, public_key_hex, handle, ~90-day TTL) is a
server-side record the user cannot independently prove or carry elsewhere.
Hardware custody without a recovery design turns a compliance gap (G1)
into a guaranteed data-loss event (G14) and violates Base Rule 1
("support identity migration or recovery without making the operator the
sole authority"). This document designs recovery **before** custody
hardens.

## Source Context

Read first:

- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
  (Base Rule 1 governs everything here; Rule 5 for binding continuity)
- Architecture plan Phase 1.0 / decisions D1, D5: `docs/architecture/service_architecture_plan.md`

Key existing code:

- Key custody today: `ansible_core/did/lib/src/did_signer.dart`,
  `did_manager.dart`, `passkeys_manager.dart` (raw hex via
  `flutter_secure_storage`; comments overclaim enclave custody)
- Anchor flow: relay `web/controllers/identity_controller.ex`
  (`challenge` → `anchor`: challenge signature + ZKP-stub + nullifier),
  `did_account_cache.ex` (handle registration, 90-day `expires_at`,
  upsert-replace), app `lib/services/relay_identity_client.dart`
- Multi-device precedent: messenger device binding —
  `messenger_controller.ex` `publish_device` verifies a
  `binding_signature` by the subject key over the device record
- Wake-push (hijack alerting reuses it): `push/wake_scheduler.ex`

---

## Constitution Review

1. **Identity/credential involved:** the user's identity (content) key,
   per-device keys, optional recovery material, and the relay anchor
   record. The issuer-assisted path (deferred) would involve a recovery
   VC.
2. **Data leaving the device:** signed public objects only — device
   attestations, the anchor object, rotation/recovery statements. The
   encrypted content-key backup leaves the device **only** under
   passphrase-derived encryption chosen explicitly by the user, and the
   relay cannot decrypt it (Base Rule 2: encrypted before it leaves the
   trusted boundary; backup is opt-in, never default-on silently).
3. **Minimum claim:** a re-anchor proof demonstrates *continuity* (control
   of the previous key, a quorum device key, or recovery material) —
   nothing about who the human is. No legal identity is ever part of
   recovery.
4. **Raw legal identity excluded:** yes. Recovery proofs are signatures;
   the deferred recovery-VC path must itself pass Rule 3/5 review before
   implementation (it is *not* approved by this document).
5. **Trust/ranking change:** re-anchoring after recovery MUST be
   reason-coded on the account (`rotation` vs `recovery`) and MAY
   temporarily reduce the trust tier for high-assurance bindings until
   re-verified (Rule 5's "define what happens when a credential is
   replaced"). Personhood bindings (nullifiers) survive recovery — they
   bind the human, not the key.
6. **Personhood binding:** none created. Existing nullifier-based
   duplicate prevention is unaffected: the new key re-binds to the same
   account identity; recovery MUST NOT mint a path to a second active
   binding for the same passport (the nullifier check already enforces
   this).
7. **Exit/rotation:** this document IS the exit design. Mandatory
   elements: user can rotate keys at will (not only after loss); user can
   re-anchor at a *different* relay with the same proofs (anchor is
   portable, relay is not an authority chokepoint); user can delete the
   encrypted backup; reduced-trust (non-hardware) mode remains available.
8. **External hosts:** a portable anchor lets any relay/host verify
   continuity independently. External hosts' acceptance of recovery
   proofs is their policy; the object format is self-certifying so they
   don't need to trust our relay's word.

**Constitution verdict:** the design below is compliant. Mandatory
elements: self-certifying anchor object, reason-coded re-anchor, no raw
legal identity anywhere in recovery, encrypted-before-leaving backup,
relay-portability of all proofs, and the hijack-resistance measures in
§Re-Anchor Protocol (silent account takeover is an "irreversible identity
harm" — conflict-priority #1).

---

## Key Hierarchy（金鑰階層）

```
Identity key (Ed25519)               ─ signs content ops, Lexicon records,
  │   "content key" — the user's        Nostr events, anchor objects.
  │   long-term public identity.        BACKUPABLE (encrypted) — never
  │                                     hardware-bound.
  ├── Device keys (P-256, hardware) ─ one per device, Secure Enclave /
  │     attested by the identity key   StrongBox, NON-exportable. Sign
  │     via a signed device record     device-scoped assertions: re-anchor
  │     (messenger binding pattern).   approvals, new-device attestations.
  └── Recovery material              ─ §D5: passphrase-encrypted backup
        of the identity key            of the identity key (NIP-49-style
                                       scrypt/XChaCha20), user-held or
                                       relay-stored ciphertext.
```

The split is the load-bearing decision: **the key that must survive
device loss (identity) is the one that stays software + backupable; the
keys that prove "a real enrolled device acted" (device) are the ones that
go into hardware.** Hardware custody strengthens day-to-day signing
without making the identity itself hostage to one device.

Signing policy: content ops continue to be signed by the identity key
(no relay/verifier changes). High-value operations (re-anchor, device
enrollment, backup deletion) require a device-key co-signature when the
account has ≥1 enrolled hardware device — this is what makes a stolen
backup passphrase alone insufficient on a multi-device account.

## D1 — Hardware keys vs signature migration（決策）

| Option | Mechanics | Pros | Cons |
|---|---|---|---|
| **A. Dual-key（建議）** | Identity stays Ed25519; per-device P-256 enclave keys attest it (hierarchy above) | No change to Lexicon/Nostr/relay verification (all Ed25519 today); identity key backupable ⇒ recovery possible; device keys genuinely hardware-bound; incremental migration | Two key types to manage; "hardware-backed" claim is per-device, not per-identity |
| B. Migrate to ES256 | Re-key identities to P-256 so the enclave holds *the* identity key | Single key type; identity key itself hardware-bound | Breaks Nostr (secp256k1/Schnorr) and current Ed25519 verification across relay/AppView/issuer; **an unexportable identity key makes device loss unrecoverable by construction** — the exact failure this design exists to prevent; ecosystem migration cost is enormous |
| C. Status quo (software Ed25519 only) | Keep raw keys in secure storage | No work | G1 stays open; no hardware custody story at all |

**Position: Option A (dual-key).** B is self-defeating — it would make
the recovery problem *unsolvable* rather than solved, because the thing
you must be able to back up (identity) becomes the thing you cannot
export. A keeps every existing verifier unchanged and gives hardware
custody where it actually helps (device-scoped proof). The "reduced-trust
mode" (Phase 1 item 2) is then precisely: an account whose only
enrollment is a software device key, surfaced as a custody-class label on
the anchor.

## D5 — Recovery mechanism mix（決策）

| Mechanism | How it works | Trust added | Launch? |
|---|---|---|---|
| **(a) Multi-device attestation（建議：launch）** | Device B scans a QR /deep-link from device A; A's enclave key signs an enrollment of B; either device can later sign a re-anchor for a replacement | None — pure user-held keys | ✅ |
| **(b) Passphrase-encrypted backup（建議：launch）** | Identity key encrypted with a key derived from a user passphrase (scrypt, NIP-49-style); ciphertext exportable as a file/QR and optionally stored on the relay (relay sees ciphertext only) | None for the file path; relay-stored ciphertext adds availability, not authority | ✅ |
| (c) Issuer-assisted recovery credential | During high-assurance verification the issuer records a recovery commitment; later re-verification of the same human yields a recovery VC accepted as re-anchor proof | Adds the issuer as a recovery authority; needs its own Rule 3/5 review (personhood ↔ key linkage) | ⏩ later |
| (d) Social recovery (M-of-N contacts) | Trusted contacts co-sign recovery | New protocol surface + coercion/collusion analysis | ⏩ explicitly out of scope |

**Position: (a) + (b) at launch, (c) designed later, (d) out of scope.**
(a) covers the common case (most users who care own ≥2 devices or can
enroll a family device) with zero new trust. (b) covers single-device
users and is also the migration vehicle for *existing* accounts (today's
raw-hex key becomes the first backup). (c) is genuinely valuable —
"verify your passport again, get your account back" — but it links
personhood verification to key control, which deserves its own
constitution review rather than a rider on this one.

Single-device users without a backup remain unrecoverable — the
onboarding flow MUST therefore offer backup creation at first run (and
nag-once after), and the account settings MUST show recovery readiness
(「可復原：2 裝置 + 備份」/「⚠ 無法復原」).

## Anchor as a Self-Certifying Object（G15 可攜性）

Today the anchor is a relay DB row. It becomes a user-signed object the
relay *stores and serves* but does not own:

```json
{
  "type": "io.trisaura.identity.anchor",
  "schema_version": 1,
  "did": "did:plc:…",
  "handle": "alice.elix.cool",
  "identity_key": "<ed25519 pubkey hex>",
  "custody_class": "hardware" | "software",
  "devices": [
    {"device_id": "…", "device_key": "<p256 pub>", "enrolled_at": "…",
     "attestation_sig": "<by identity key>"}
  ],
  "prev_anchor_cid": "<hash of the previous anchor object or null>",
  "reason": "initial" | "rotation" | "recovery" | "device_change",
  "created_at": "…",
  "sig": "<by identity key (+ device co-sig when enrolled)>"
}
```

Properties: hash-chained (`prev_anchor_cid`) so the key history is an
auditable chain; self-certifying (anyone can verify the chain without
trusting the relay); carries `schema_version` from day one (Phase 0
convention); the relay's `did_accounts` row becomes a *cache* of the
latest anchor. The chain is intentionally `did:plc`-shaped (operation log
with rotation) without depending on PLC infrastructure — a future
compatibility export stays possible.

## Re-Anchor Protocol

Three flows, all producing a new anchor object with the appropriate
`reason`:

1. **Rotation (old key available):** new anchor signed by *both* old and
   new identity keys. Relay verifies the chain and swaps immediately. No
   delay — possession of the old key is full authority.
2. **Device change:** add/remove device records; signed by the identity
   key + an enrolled device key. Immediate.
3. **Recovery (old key lost):** new anchor carries a `recovery_proof`:
   either (a) a signature by an **enrolled device key** from the previous
   anchor, or (b) the decrypted-backup identity key itself signing (which
   collapses to flow 1). Path (a) — device survives, identity key lost —
   is the genuinely new verification path.

**Hijack resistance (mandatory, conflict-priority #1):** for `recovery`
re-anchors the relay (i) immediately notifies **all** enrolled devices
via the existing content-free wake push + a local notification
(`identity_alert`), (ii) holds the re-anchor in a **pending state for a
grace window** (default 72h, config) during which any previously-enrolled
key can sign a veto that freezes the account for manual/issuer-assisted
resolution, and (iii) reason-codes the event permanently in the anchor
chain. Flows 1–2 (old key present) skip the window — there is nothing a
hijacker gains that they didn't already have. Handle re-binding to a
*different* DID (handle takeover) is out of scope here and stays governed
by handle-expiry policy.

**Relay portability:** because the anchor chain is self-certifying, the
same chain + proofs can be presented to a different relay
(`POST /api/v1/identity/anchor` equivalent). The receiving relay applies
its own grace-window policy. The relay is thus a *availability* provider,
not a *continuity* authority — Base Rule 1 satisfied structurally.

## Migration of Existing Accounts

Existing accounts (raw-hex Ed25519, no anchor object) migrate lazily: on
first launch after the feature ships, the app (1) offers backup creation
(D5-b) using the existing key, (2) creates anchor v1 with
`reason: "initial"`, `custody_class: "software"`, and (3) when Phase 1
hardware enrollment lands, device keys attach via flow 2. No flag-day, no
re-registration.

## Non-Goals

- Social recovery (D5-d), recovery-credential implementation (D5-c — a
  follow-up design), handle-squatting policy, PLC genesis compatibility,
  messenger session re-establishment after recovery (existing messenger
  device flows handle it; verify in implementation), multi-identity
  profiles.

## Implementation Task Outline（後續 plan 的骨架）

- [ ] **Task 1 (rust/core):** anchor object model + canonical encoding +
      chain verification in `ansible_rust_core`; Dart bindings.
- [ ] **Task 2 (app/store):** anchor chain persistence; backup
      create/restore UX (scrypt params per NIP-49; export as file + QR);
      recovery-readiness indicator in settings + onboarding backup offer.
- [ ] **Task 3 (app/did):** device-key abstraction (enclave-backed P-256
      with software fallback ⇒ custody class); device enrollment QR flow
      (reuse messenger binding pattern).
- [ ] **Task 4 (relay):** anchor store (chain-verifying), re-anchor
      endpoints for flows 1–3, grace-window + veto + `identity_alert`
      wake, reason-coded account history; `did_accounts` becomes a cache.
- [ ] **Task 5 (app):** recovery wizard (restore-from-backup,
      approve-from-other-device), veto UX on enrolled devices.
- [ ] **Task 6:** compliance review update (G1/G14/G15 sections) + spec
      doc for external hosts.

## Definition of Done (for this design)

- D1 and D5 positions reviewed and accepted (or amended) by the owner.
- The anchor object format reviewed against Phase 2's planned
  ops/snapshot schema so the two don't diverge (architecture plan
  sequencing note).
- Follow-up implementation plan(s) written from the task outline, each
  with its own constitution review.
