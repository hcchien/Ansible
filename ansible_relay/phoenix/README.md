# ansible_relay/phoenix — Elixir/Phoenix Relay (V1.1)

> **狀態：Q2 起始** — Dart shelf server 已移除，此目錄放置未來的 Elixir/Phoenix 實作。

## 對應 V1.1 組件

- **Comp C**: Carrier-Grade Relay / Genesis Relay
- **Comp D**: The First Forum / Aggregator & Forum Engine（可獨立部署）

Genesis Hosting reference: [`../../docs/architecture/genesis_hosting.md`](../../docs/architecture/genesis_hosting.md).
Security launch checklist: [`../../docs/security/sosp.md`](../../docs/security/sosp.md).

## 預計結構

```
ansible_relay/phoenix/
├── apps/
│   ├── relay/          # Comp C: connection manager, ETS DID cache, GCS blob handler
│   │   ├── lib/relay/
│   │   │   ├── cluster.ex              # libcluster topology + PubSub
│   │   │   ├── presence.ex             # Phoenix Presence: users + verified status
│   │   │   ├── connection_manager.ex   # GenStage, backpressure
│   │   │   ├── identity_cache.ex       # ETS: Verified DID → expiry
│   │   │   ├── zkp_key_registry.ex     # pinned circuit VK versions
│   │   │   ├── gossipsub_topic.ex      # /ansible/ops/v1 topic validation
│   │   │   ├── gossip_enforcer.ex      # Gossipsub peer scoring / disconnects
│   │   │   ├── abuse_detector.ex       # Token Bucket rate limiting
│   │   │   ├── log_redactor.ex         # IP/DID separation for ops logs
│   │   │   ├── binary_stream.ex        # Protobuf CrdtOp decode + validation
│   │   │   ├── pubsub_forwarder.ex     # GCP Pub/Sub handoff to Forum
│   │   │   ├── blob_handler.ex         # Oban job → GCS upload
│   │   │   └── sig_verifier.ex         # Rustler NIF bridge
│   │   └── ...
│   └── aggregator/     # Comp D: Op verifier, materialized views, LiveView
│       ├── lib/aggregator/
│       │   ├── pubsub_consumer.ex      # GCP Pub/Sub ingest from Relay
│       │   ├── op_verifier.ex          # Rustler NIF → Rust Ed25519 verify
│       │   ├── forum_engine.ex         # CRDT fold → PostgreSQL
│       │   ├── snapshot_exporter.ex    # signed snapshots for new hosts
│       │   ├── seo_renderer.ex         # crawlable public HTML
│       │   └── forum_live.ex           # Phoenix LiveView
│       └── ...
├── config/
├── mix.exs
└── ...
```

## 關鍵技術依賴

| 功能 | 套件 |
|------|------|
| HTTP/WebSocket 伺服器 | `phoenix` + `bandit` |
| 身分狀態快取 | `:ets` (built-in) |
| 非同步任務（GCS 上傳）| `oban` |
| Rust 簽章驗證 | `rustler` (NIF) |
| 資料庫 | `ecto` + `postgrex` (Cloud SQL) |
| 物件儲存 | `goth` + `google_api_storage` (GCS) |
| 叢集拓撲 | `libcluster` |
| 使用者連線狀態 | `phoenix_presence` |
| Relay → Forum 串流 | GCP Pub/Sub |

## ETS Identity Cache / Challenge 設計

```elixir
# 表名: :verified_did_cache
# Key:   DID string  (e.g. "did:key:z6Mk...")
# Value: {public_key_hex, verified_at, expires_at}

# 表名: :identity_challenges
# Key:   DID string
# Value: {challenge, issued_at, expires_at}
#
# POST /api/v1/identity/challenge:
:ets.insert(:identity_challenges, {did, challenge_entry})

# POST /api/v1/identity/anchor:
# - verify challenge_signature
# - consume challenge exactly once

:ets.new(:verified_did_cache, [:set, :public, :named_table, read_concurrency: true])
:ets.new(:identity_challenges, [:set, :public, :named_table])

# Phase 1 完成後寫入:
:ets.insert(:verified_did_cache, {did, {pubkey_hex, verified_at, expires_at}})

# Phase 2 每次簽章驗證:
case :ets.lookup(:verified_did_cache, did) do
  [{^did, {pubkey_hex, _verified, expires}}] when expires > now -> verify_sig(pubkey_hex, sig)
  _ -> {:error, :did_not_verified}
end
```

## Rustler NIF 簽章驗證

```rust
// native/relay_nif/src/lib.rs
#[rustler::nif]
fn verify_ed25519(pubkey_hex: &str, message: Binary, sig_hex: &str) -> bool {
    // ring::signature::UnparsedPublicKey::verify(...)
}
```

## ZKP Verification Key Pinning

Phase 1 anchoring requires both `zkp_circuit_version` and
`verification_key_hash`. The relay accepts only active entries configured under
`:zkp_verification_keys`.

```elixir
config :ansible_relay,
  zkp_verification_keys: [
    %{
      version: "passport_v1_dev",
      hash: "sha256:dev-passport-v1-placeholder",
      status: :active
    }
  ]
```

Before public launch, replace the dev hash with the audited verification key
hash and keep retired keys in config only for explicit migration windows.

## Gossipsub Topics

Canonical Op topics follow:

```text
/ansible/ops/v1/{network}/{scope}
```

Reference: [`../../docs/protocol/gossipsub_topics.md`](../../docs/protocol/gossipsub_topics.md).

Production public Ops use:

```text
/ansible/ops/v1/mainnet/global
```

## GCP 部署

- Relay: GKE Autopilot（Regional Phoenix cluster, ETS 透過 Phoenix.PubSub 跨節點同步）
- Aggregator: GKE C2 compute-optimized（Rustler 簽章驗證 CPU 密集）
- Database: Cloud SQL PostgreSQL（read replica for forum queries）
- Blob: Google Cloud Storage（encrypted Ops, multi-region）
- Edge: Cloud CDN + Cloud Armor for the First Forum
- Regions: Taiwan, Netherlands, United States as the Genesis benchmark

## Genesis Hosting TODO

- [ ] Add `libcluster` and regional GKE topology config.
- [ ] Add Phoenix Presence for active users and verified DID status.
- [ ] Propagate verified DID cache updates across relay nodes.
- [x] Pin ZKP circuit version and Verification Key hash for Phase 1 anchoring.
- [x] Define and validate Gossipsub Op topic naming convention.
- [ ] Implement Gossipsub peer scoring and disconnect reason codes.
- [x] Implement Token Bucket abuse detection for DID Op submission.
- [ ] Implement Token Bucket abuse detection for peer invalid-message limits.
- [ ] Implement log redaction that prevents IP/DID joins in GCP logs.
- [ ] Add Protobuf binary stream handler for `CrdtOp`.
- [ ] Forward accepted Ops to GCP Pub/Sub.
- [ ] Implement Forum Pub/Sub consumer and Rustler batch verifier.
- [ ] Add PostgreSQL materialized projections and logical replication.
- [ ] Add signed snapshot exporter for third-party aggregators.
- [ ] Add rendered-content verification tools for raw Op comparison.
- [ ] Define append-only hash chain and moderation/tombstone Ops.
- [ ] Enforce double verification for Forum ingestion: valid signature and active DID anchor.
