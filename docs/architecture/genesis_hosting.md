# Genesis Hosting Architecture

> Status: Draft  
> Scope: Genesis Nodes, Component C Firehose Relay, Component D AppView Aggregator  
> Goal: make the founding host a protocol benchmark, not a privileged center.

Security launch checklist: [`../security/sosp.md`](../security/sosp.md).

---

## 1. Genesis Node Role

The founding team operates the first production host as the **Genesis Nodes**.
This host exists for two reasons:

- Ensure the early network is usable before there are many independent hosts.
- Publish a concrete benchmark for relay latency, sync correctness, public
  rendering, auditability, and deployment operations.

Genesis Hosting must not become a central authority. Every hosted service must
preserve the protocol rules that let future hosts independently verify, replay,
and mirror the network.

---

## 2. Component C — Firehose Relay

The Genesis Relay is the reference implementation for high-throughput,
low-latency AT Protocol Op ingestion and Firehose subscription.

Transition note: this section describes the current AT Protocol / `did:plc`
compatibility and AppView path. It is not the only public federation identity
path. The local-first federation direction is defined in
[`../protocol/tris_aura_federation_strategy_v0.1.md`](../protocol/tris_aura_federation_strategy_v0.1.md):
Nostr uses `did:nostr` / public keys from the app, and ActivityPub uses
relay-domain actor URLs owned by the distribution relay.

### C-1 Distributed Erlang Cluster

- Runtime: Phoenix on GKE, clustered with `libcluster`.
- Goal: any Phoenix instance can accept a user XRPC connection and publish state
  to the rest of the relay cluster.
- Identity state: active DID cache is synchronized across nodes through
  Phoenix.PubSub / Presence-compatible broadcasts, so a user changing regions
  does not need to re-register.
- Deployment: at least three GCP regions for the Genesis benchmark:
  Taiwan, Netherlands, and United States.

### C-2 Load Balancing and Presence

- Runtime entrypoint: GCP Ingress in front of regional Phoenix deployments.
- Presence: Phoenix Presence tracks active app connections and their current
  DID status and Reputation tier.
- Relay handoff: reconnecting through another region should preserve active
  status if the DID cache entry is still valid.

### C-3 Firehose Subscription and Filtering Target

- Target Relay behavior subscribes to the global atproto Firehose via WebSocket:
  `wss://{upstream}/xrpc/com.atproto.sync.subscribeRepos`
- Elixir pattern matching filters events whose Lexicon `$type` starts with
  `io.trisaura.*`.
- Accepted events are forwarded to Component D through GCP Pub/Sub.
- Rejected / irrelevant events are dropped without logging content.

Status (2026-06): Component D now exists as `ansible_appview/phoenix` — it
polls the relay op delta endpoint and folds it into a PostgreSQL projection
(see the AppView README). The global atproto Firehose WebSocket subscription
and GCP Pub/Sub forwarding described above remain unimplemented; ingestion is
relay-poll based. Direction update: per the
[service architecture plan](service_architecture_plan.md) (Phase 3 /
decision D2), single-region push will use Phoenix Channels rather than GCP
Pub/Sub; Pub/Sub (or NATS) is reconsidered only at the Phase 5 multi-region
stage.

### C-4 XRPC Ingestion Handler

- Input: App sends `com.atproto.repo.createRecord` XRPC requests.
- Current MVP path:
  1. Parse and validate the Lexicon record structure.
  2. Verify `repo` DID against the active DID cache.
  3. Verify the Ed25519 `commit_sig` over the CBOR-serialised record.
  4. Append the accepted record to OpStore and return a stub CID.
- Target path still needs duplicate-CID enforcement, Firehose emission, and GCP
  Pub/Sub forwarding for Component D.
- Benchmark: record parse, verification, dedup, and publish latency.

### C-5 SLA and Operations

- Publish relay SLOs for availability, p95 ingest latency, duplicate rejection,
  invalid-record rejection, regional failover time, and Pub/Sub delivery lag.
- Export metrics to GCP Cloud Monitoring.
- Alerts must distinguish infrastructure failure from protocol-level rejection.

---

## 3. Component D — AppView Aggregator & The First Forum

The AppView is the public aggregation and rendering layer for Tris-Aura. It is
the first Web entrypoint, but it must remain independently reproducible from
raw Lexicon records and MST commits.

### D-1 Global View Aggregator

- Runtime: Phoenix receives `io.trisaura.*` events from all relay stations
  through GCP Pub/Sub.
- Verification: Rustler NIFs perform high-volume parallel validation when
  folding records into public views.
- Materialization: accepted records are folded into forum projections suitable
  for list pages, thread pages, moderation views, and export snapshots.

### D-2 Reputation Labeler

- The AppView hosts a `com.atproto.label` compatible Labeler service.
- Assigns tiers: Basic / DNS Verified / Verified Human (see spec v2.0 §11).
- Labels are attached to DID records and included in rendered provenance.

### D-3 Multi-Tenant Rendering

- The public UI can render multiple channels or communities from the same
  aggregation layer.
- Every rendered item must expose its source DID, Reputation tier, and
  record provenance.
- Hosted presentation must clearly distinguish Genesis-hosted rendering from
  protocol ownership.

### D-4 SEO Engine

- Phoenix LiveView renders HTML statically optimized for search engines.
- Goal: prevent decentralised content from becoming P2P-only islands.
- Pages should include canonical URLs, structured metadata, and stable thread
  paths derived from content identity (AT-URI: `at://did/collection/rkey`).

### D-5 PostgreSQL Landing and Fast Rebuild

- Database: Cloud SQL PostgreSQL for public projections.
- Replication: logical replication supports read replicas and future host
  bootstrapping.
- Snapshot: Genesis Hosting should publish signed MST snapshots so independent
  aggregators can quickly rebuild historical forum state.

### D-6 CDN and Edge Protection

- Cloud CDN accelerates public forum assets and cacheable HTML.
- Cloud Armor filters large crawlers, volumetric attacks, and suspicious
  traffic patterns without changing the underlying protocol state.

---

## 4. Updated Lifecycle

| Phase | Relay Tasks | AppView Tasks | Key Deliverables |
|---|---|---|---|
| P1 Alpha | Implement XRPC ingestion; run single GKE relay test node. | Build text-only Web aggregator; validate Lexicon rendering. | Internal end-to-end post flow. |
| P2 Beta | Host first global relay cluster; enable Firehose subscription. | Launch official Tris-Aura forum with Web browsing. | Seed-user invite and public read path. |
| P3 RC | Publish one-command Relay Docker image and deployment docs. | DNS Handle verification + Reputation Labeler integration. | Multi-host ecosystem path. |
| P4 Production | Relay SLA monitoring and regional failover playbooks. | AI Agent Comp F for Firehose summarisation and filtering. | Automated operations and AI content management. |

---

## 5. Security Requirements for the First Host

The mandatory pre-launch security policy lives in
[`../security/sosp.md`](../security/sosp.md). Genesis Hosting must satisfy that
checklist before public launch.

### Transparent Proof

The public forum must expose verification tools that let users compare rendered
content with raw AT-URI records. A user should be able to inspect the source DID,
Reputation tier, signature status, record CID, and MST inclusion path for a
rendered post.

### No Centralized Delete Privilege

Once a record enters the relay layer and is broadcast, the Genesis Host cannot
silently delete it without breaking the append-only MST commit chain. Moderation
and legal compliance must be represented as additional signed Tombstone records
or rendering policies, not hidden mutation of protocol history.

### Reproducible Public Views

The First Forum must be rebuildable from raw Lexicon records plus public
rendering rules. PostgreSQL projections are acceleration artifacts, not the
source of truth.

---

## 6. Genesis Hosting TODO

### Component C — Firehose Relay

- [ ] Add `libcluster` topology configuration for GKE regional clustering.
- [ ] Implement Phoenix.PubSub propagation for active DID cache updates.
- [ ] Add Phoenix Presence tracking for connected users and DID status.
- [ ] Define regional GCP Ingress layout for Taiwan, Netherlands, and United States.
- [x] Implement partial XRPC `com.atproto.repo.createRecord` handler.
- [ ] Add WebSocket Firehose subscription with `io.trisaura.*` filter.
- [ ] Forward accepted records to GCP Pub/Sub for Component D.
- [ ] Add relay metrics: parse latency, signature verification latency, ingest p95,
  duplicate-CID rejection count, invalid-record rejection count, Pub/Sub lag.
- [ ] Publish relay SLA targets and alert rules.
- [x] Implement SOSP DID-level Token Bucket rate limiting.
- [ ] Implement SOSP peer invalid-message Token Bucket rate limiting.
- [ ] Implement SOSP log redaction for IP/DID separation.

### Component D — AppView Aggregator

- [ ] Implement Phoenix Pub/Sub consumer for relay-accepted records.
- [ ] Add Rustler-backed batch Ed25519 verifier for aggregation.
- [ ] Build text-only forum projection pages for P1.
- [ ] Add Reputation Labeler service (com.atproto.label compatible).
- [ ] Add multi-tenant channel/community rendering model.
- [ ] Display source DID, Reputation tier, and record provenance on rendered content.
- [ ] Implement SEO metadata using AT-URI canonical paths.
- [ ] Store materialized forum projections in PostgreSQL.
- [ ] Add logical replication configuration and MST snapshot export.
- [ ] Put Cloud CDN and Cloud Armor deployment docs under infrastructure docs.
- [ ] Enforce double verification: valid Ed25519 signature and non-expired DID.
- [ ] Preserve verification status in rendered provenance.
- [ ] Track LLM plugin and MCP agent access backlog in
  `docs/superpowers/todos/2026-05-16-llm-plugin-mcp-access.md`.

### Anti-Centralization

- [ ] Define append-only MST commit chain format and snapshot metadata.
- [ ] Add rendered-content verification UI for raw AT-URI comparison.
- [ ] Define Tombstone Lexicon type for moderation (no silent deletion).
- [ ] Publish signed snapshot metadata and replay instructions for third-party hosts.
- [ ] Document governance rules for Genesis Host operational intervention.

### SOSP Launch Gate

- [ ] Complete P1 Passkeys key isolation test.
- [ ] Complete P2 Relay penetration test.
- [ ] Complete P3 GCP infrastructure scan.
- [ ] Close all critical/high severity findings before public launch.
