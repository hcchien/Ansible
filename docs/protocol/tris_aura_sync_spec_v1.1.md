# Tris-Aura Sync Protocol Spec v1.1

> Status: **Superseded** by [`tris_aura_sync_spec_v2.0.md`](./tris_aura_sync_spec_v2.0.md)  
> Supersedes: `ansible_sync_spec_v0.1.md` (removed)  
> Owners: core, identity, sync

---

## 1. 兩段式驗證概覽

| | Phase 1 — Identity Anchoring | Phase 2 — Daily Operations |
|---|---|---|
| 觸發時機 | 首次使用 / 憑證過期 | 每次發文 / 編輯 |
| 運算強度 | 高（ZKP Groth16 + DID 生成） | 輕量（Ed25519 簽章） |
| 耗時 | ~5–15 秒 | <10 ms |
| 手機耗電 | 高 | 極低 |

---

## 2. Phase 1 — Identity Anchoring

```
App                           Relay (Elixir/Phoenix)
 |                                 |
 |   [local: read PassportData]    |  ← MockNfcPassportReader (real NFC: Q3)
 |   [local: generate DID keypair] |
 |                                 |
 |-- POST /api/v1/identity/challenge
 |   body: { did: "did:key:z6Mk..." }
 |<-- 200 OK { challenge, expires_at }
 |                                 |
 |   [local: generate Self-Issued VC]
 |   [local: ZKP circuit (Rust)]   |
 |   [local: sign challenge]       |
 |                                 |
 |-- POST /api/v1/identity/anchor  |
 |   body: {                       |
 |     did: "did:key:z6Mk...",      |
 |     zkp_proof: <bytes>,          |
 |     zkp_circuit_version: "passport_v1_dev",
 |     verification_key_hash: "sha256:...",
 |     nullifier: <hex>,            |
 |     public_key: <hex>,           |
 |     challenge: <nonce>,          |
 |     challenge_signature: <hex>   |
 |   }                             |
 |                                 |
 |                   [verify ZKP via Rustler NIF]
 |                   [verify + consume challenge]
 |                   [check nullifier not reused]
 |                   [write to ETS verified_did_cache]
 |<-- 200 OK { expires_at: ... } --|
```

### Nullifier Uniqueness
The Relay rejects any anchor request whose `nullifier` already exists in the database → prevents one passport from creating multiple identities.

---

## 3. Phase 2 — Op Dispatch (Daily Operations)

```
App                           Relay (Elixir/Phoenix)
 |                                 |
 |  [create CRDT Op (Yrs delta)]   |
 |  [sign: Ed25519(opId || payload)]
 |                                 |
 |-- libp2p Gossipsub broadcast -->|  (or fallback: POST /api/v1/ops)
 |   body: {                       |
 |     op_id: <uuid>,              |
 |     author_did: "did:key:...",  |
 |     entity_type: "post",        |
 |     entity_id: <uuid>,          |
 |     payload: <base64 yrs delta>,|
 |     signature: <hex ed25519>    |
 |   }                             |
 |                                 |
 |         [ETS lookup: author_did]|
 |         [verify Ed25519 sig]    |
 |         [async: write blob GCS] |
 |         [broadcast Gossipsub]   |
 |<-- 202 Accepted { log_id } -----|
```

### No ZKP Re-run
Phase 2 verifies only the Ed25519 signature against the cached public key in ETS. This eliminates the need for ZKP re-computation on every post.

---

## 4. Op Envelope

Canonical schema: [`ops.proto`](./ops.proto).

```protobuf
message CrdtOp {
  string op_id       = 1;  // UUID v4
  string author_did  = 2;  // did:key:z6Mk...
  string entity_type = 3;  // board | thread | post | reaction
  string entity_id   = 4;  // UUID v4
  string op_type     = 5;  // insert | update | delete | crdt_merge
  bytes  payload     = 6;  // Yrs binary delta
  bytes  signature   = 7;  // Ed25519 signature (64 bytes)
  int64  created_at_ms = 8;  // Unix timestamp ms
}
```

---

## 5. Replay Protection

- Each Op carries a unique `op_id` (UUID v4).
- The Relay stores processed `op_id` values; duplicate ops are rejected with `409 Conflict`.
- Phase 1 anchoring includes a server-issued random `challenge` nonce consumed exactly once by `/api/v1/identity/anchor`.

---

## 6. Transport

| Layer | Protocol | Notes |
|-------|----------|-------|
| P2P broadcast | libp2p Gossipsub | primary path (Comp B); topics follow [`gossipsub_topics.md`](./gossipsub_topics.md) |
| Fallback | HTTPS POST to Relay | for restricted networks |
| Encryption in transit | Noise protocol (libp2p) | Ed25519 ephemeral keys |

---

## 7. Client-side Op Queue (Offline-first)

Ops that cannot be immediately sent are persisted in the local SQLite `ops_queue` table (Drift schema: `OpsQueue`).

Retry policy:
- status = `pending` → retry on reconnect
- status = `rejected` → log error, do not retry
- status = `synced` → can be pruned after 7 days

---

## 8. TODO Items

- [x] Define Protobuf schema file (`ops.proto`)
- [x] Implement Phase 1 challenge-response nonce
- [x] Define ZKP circuit verification key hash versioning
- [x] Specify Gossipsub topic naming convention (`/ansible/ops/v1`)
- [ ] Define GCS bucket structure for encrypted Op blobs

---

## 9. Genesis Hosting Benchmark

The founding team operates the first production host as **Genesis Nodes**. This
is a benchmark implementation for Component C (Carrier-Grade Relay) and
Component D (The First Forum), not a central authority.

Reference architecture: [`../architecture/genesis_hosting.md`](../architecture/genesis_hosting.md).

Protocol-facing requirements:

- Pre-launch security requirements are tracked in
  [`../security/sosp.md`](../security/sosp.md).
- Relay clusters must preserve verified DID status across regional handoff
  without requiring users to rerun ZKP while the DID cache entry remains valid.
- Accepted Ops must be forwarded as canonical Protobuf envelopes, not
  relay-specific JSON shapes.
- Public forum rendering must expose source DID and Op provenance.
- Rendered pages must be reproducible from raw Ops plus public rendering rules.
- Once broadcast, Ops are append-only protocol history. Moderation must use
  additional signed Ops, tombstones, or rendering policies.

Genesis Hosting protocol TODO:

- [ ] Define distributed verified-DID cache propagation events.
- [ ] Define peer-scoring reason codes for invalid Gossipsub propagation.
- [ ] Define Pub/Sub message envelope for Relay → Forum handoff.
- [ ] Define append-only Op hash chain format.
- [ ] Define moderation/tombstone Op types and rendering semantics.
- [ ] Define rendered-content verification payload for Web users.
- [ ] Define encrypted Op envelope for AES-256-GCM payloads.
- [ ] Define biometric-gated Op signing requirements for App clients.
- [ ] Define duplicate-nullifier DID suspension semantics.
- [ ] Define log-redaction fields for IP/DID separation.
