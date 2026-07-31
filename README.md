# Ansible — Tris-Aura Hybrid Network V2.0

A local-first, multi-protocol forum and identity stack. Participants are
pseudonymous but Sybil-resistant through layered trust: base-level accounts use
app-held DID keys, while higher trust tiers come from accepted credentials or
other explicit verification paths. The canonical user identity is `did:elix`
(domain-independent, self-certifying, portable across relays); `did:key` is the
wallet/credential holder and `did:web` is reserved for issuers. AT Protocol /
`did:plc` is an **opt-in Bluesky bridge**, not the canonical identity. Nostr
publication, Relay-side ActivityPub projection, Forum Host APIs, and
app-mediated web sessions exist as partial MVP slices.

## Architecture

```
ansible_node/app          Flutter mobile/desktop node — UI, local Repo, Passkeys auth
ansible_core/
  domain/                 Business logic, auth contracts, sync interfaces
  store/                  Drift (SQLite) — atproto Repo, MST, Op queue
  did/                    DID key management: did:elix (canonical) + did:key (wallet);
                          did:plc bridge / did:web (flutter_rust_bridge FFI)
  vc/                     Lexicon record models, MST engine (Rust FFI)
ansible_rust_core/        Rust crate — Ed25519, MST, Lexicon signing, atproto repo
ansible_relay/phoenix/    Elixir/Phoenix — co-located Relay, Forum Host, web sessions,
                          ActivityPub/XRPC compatibility, discovery APIs, op firehose
ansible_appview/phoenix/  Elixir/Phoenix — AppView aggregator: folds the relay op
                          firehose into a PostgreSQL read model, follow graph, and a
                          scalable following/home feed (fan-out-on-read + write)
ansible_issuer/go/        Go — W3C Verifiable Credential issuer (did:web), TW digital
                          identity provider integration, Postgres-backed stores
ansible_distribution_frontend/
                          Node/static web frontend — Forum Host public views and
                          app-approved web-session flow
docs/
  protocol/               Sync spec v2.0, AT Protocol Lexicon conventions
  architecture/           Genesis hosting, full system architecture, TW VC wallet
  deployment/             Cloud Run deploy steps, scaling/operations runbook
  security/               SOSP pre-launch security policy
```

## Identity Flow (Current MVP)

```
User taps "建立帳號"
  → app creates/loads a local Ed25519 identity key
  → derives the canonical did:elix (+ a did:key wallet alias) and publishes a
    self-certifying anchor; a did:plc bridge alias is minted only on opt-in
  → Relay marks DID as "Active"; Reputation Labeler tier = Basic
```

Hardware-held signing keys and explicit reduced-trust mode are still compliance
gaps; do not treat current secure-storage-backed key paths as complete Secure
Enclave / StrongBox custody.

## Public Distribution Flow (Current MVP)

```
User creates public/unlisted content or a forum intent
  → private content remains local and fail-closed
  → app can publish selected public content to user-selected Nostr relays
  → app can submit signed Forum Host intents for hosted boards
  → relay can project accepted publication intents to ActivityPub MVP surfaces
  → distribution frontend reads public Forum Host APIs and uses httpOnly
     app-approved web sessions for scoped writes
```

## Component Status

| Component | Status | Notes |
|---|---|---|
| Local app and store | ✅ MVP | Flutter app, Drift store, local content, hosted-board projections |
| Relay / Forum Host Phoenix service | ✅ MVP / partial | Discovery, Forum Host metadata/boards, signed intents, web sessions, ActivityPub/XRPC compatibility |
| Distribution frontend | ✅ MVP / partial | Public Forum Host views and app-approved DID web-session flow |
| Nostr adapter | ✅ partial | App-side publication/settings/retry surfaces; production key custody remains incomplete |
| ActivityPub adapter | ✅ partial | Relay-side actor/WebFinger/outbox/projection/retry (outbound); full federation behavior remains incomplete |
| Inbound federation (curated AP ingest) | ✅ MVP | Pull-based ingest of an admin-curated actor allowlist into an isolated external lane (`source=activitypub`, never `sig_verified`); surfaces only on boards with `external_inclusion` (mutually exclusive with 真人版) AND per-user opt-in, badged with origin + compliance level; never on verified surfaces (regression-tested) |
| `did:elix` identity + AT Protocol bridge | ✅ did:elix canonical; bridge pending | Canonical `did:elix` (self-certifying anchor chain + cross-relay resolution v0 at `GET /api/v1/identity/did/:did`) with a `did:key` wallet alias; Issuer Trust Registry gates VC issuers. XRPC `createRecord`/`resolveHandle` remain. The `did:plc` *creation* path has been retired; the real DAG-CBOR opt-in Bluesky bridge is future work (Phase D) |
| AppView Aggregator | ✅ MVP | `ansible_appview/phoenix` folds the relay op firehose into a PostgreSQL read model (follow graph, feed items) and serves the following/home feed; ETS by default, Redis + read replica for scale-out |
| Following / home feed | ✅ MVP | Fan-out-on-read over the federated follow set, plus Phase C fan-out-on-write home timelines (Redis ZSET + per-item object cache) with celebrity hybrid and cold-reader fallback |
| Discovery | ✅ MVP | Who-to-follow + explore + unified people/post search (AppView), board search (relay), in-app Discover screen; public-only, reputation-tier ranked; bilingual trigram search |
| VC Issuer | ✅ MVP / partial | `ansible_issuer/go` issues W3C VCs (`eddsa-jcs-2022`, did:web `/.well-known/did.json`); TW provider production adapter is the remaining external integration |
| DNS Handle verification | 🔜 future | DNS TXT + HTTPS /.well-known lookup |
| Reputation Labeler | ✅ partial | VP-to-tier paths exist; tiers propagate through relay → AppView → app badges and now gate posting per board (`posting_policy.min_post_tier`, relay-enforced); standalone labeler service is future work |
| Trust-gated boards（真人驗證版）| ✅ MVP | Hosts can require `verified_human` to post; enforced at both relay write chokepoints (signed ops + web sessions), surfaced in app (badge, gated composer, upgrade CTA) and web frontend |
| Content reporting & moderation | ✅ MVP | Reason-coded reports (app signed intents + web sessions, tier-aware rate limits), moderator console on the web frontend (queue/dismiss/remove/lock + audit), host-scoped tombstones rendered in listings, web **and** app (authors keep their content + see the reason); moderation of your content raises a local notification |
| Notifications | ✅ Phase A + B pipeline | Pure local projection — replies/follows/messages/moderation outcomes fold into a local table during sync (zero new server surface); in-app feed, unread bell badge, per-category settings. Phase B wake-push pipeline (relay token registry + debounced `{"hint":"sync"}` scheduler + app opt-in) ships end-to-end; only APNS/FCM platform credentials remain (see getting-started) |
| AI Agent Comp F | 🔜 P4 | Summarisation and filtering over Firehose stream |

## Social Graph Direction

Follow users and follow boards are implemented as a local-first social
subscription layer. User follows build a Following feed from accepted actor
relationships. Board follows build the same feed from accepted board
relationships and remote board follows toggle `BoardSyncConfig`.

Follows carry an explicit visibility: **`federated`** follows are published to the
relay as signed `follow` ops so the AppView can build a follow graph and serve a
scalable home feed; **`localOnly`** follows never leave the device and resolve
through the local delta filter. The app reads the following feed either by
fan-out-on-read (`POST /api/v1/timeline` over the federated follow set) or, when
enabled, by the server-materialized fan-out-on-write home timeline
(`GET /api/v1/home`), which degrades gracefully back to fan-out-on-read for cold
readers or on cache loss. See `docs/deployment/scaling_operations.md`.

Because the network is local-first, discovery (finding people/boards to follow)
is a global-aggregation concern served by shared indexers, not the client: the
AppView serves who-to-follow, explore, and people/post search; the relay serves
board search over host-owned boards. The app publishes the user's public profile
(handle/display name) as a `profile` op so others can find them. Discovery indexes
public data only and ranks by reputation tier. See
`docs/deployment/scaling_operations.md`.

Follow data must not contain Wallet credential payloads or Taiwan digital
identity assertions.

## TW Provider Issuance Direction

The issuer supports a production-shaped TW provider flow with single-use auth
state, replay rejection, provider proof verification boundaries, and holder-bound
credential issuance after callback verification. Raw provider assertions and
government identity fields stay inside the issuer boundary and must not be
logged or stored.

## Project Navigation

- **[docs/ROADMAP.md](docs/ROADMAP.md)** — master planning index: what is in
  flight, next, parked, done, and known compliance gaps, with links to every
  spec/plan under `docs/superpowers/`.
- **[docs/architecture/service_architecture_plan.md](docs/architecture/service_architecture_plan.md)**
  — how the services evolve to launch and scale: five sequenced phases (key
  custody → data-plane integrity → push distribution → federation completion
  → scale-out) with the full gap inventory and open design decisions.
- **[docs/getting-started-dev.md](docs/getting-started-dev.md)** — full dev
  environment setup (all six toolchains), per-service run commands, tests,
  and common pitfalls.
- **[docs/join-development.md](docs/join-development.md)** — contributor
  entry point: choose an area, follow the constitution gate, run the smallest
  relevant checks, and hand off a focused change safely.
- **Governance:** [AGENTS.md](AGENTS.md) mandates the constitution gate — read
  the [engineering constitution](docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md)
  and [compliance review](docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md)
  before changing identity, sync, federation, credentials, or ranking behavior.
- **One-command workflows:** `make help` lists test/analyze targets per
  component; `make dev` boots the backend stack (postgres + relay + appview +
  issuer + frontend) via [docker-compose.yml](docker-compose.yml).

## Getting Started

For the complete guide (databases, env vars, pitfalls), see
[docs/getting-started-dev.md](docs/getting-started-dev.md). Short version:

### Prerequisites

```bash
# Rust toolchain
curl https://sh.rustup.rs -sSf | sh

# Flutter SDK ≥ 3.10 on PATH
# Elixir ≥ 1.19 + Erlang/OTP 27+ on PATH (relay + appview)
# Go ≥ 1.25 on PATH (issuer)
# PostgreSQL running locally (shared by relay/forum-host; separate DB for appview)
```

### Build (first time)

```bash
cd /path/to/Ansible

# 1. Build Rust crate + generate Dart FFI bindings + Drift
./setup_codegen.sh

# 2. Start co-located Elix Relay / Forum Host Phoenix service
cd ansible_relay/phoenix
mix deps.get && mix ecto.create && mix ecto.migrate
mix run --no-halt          # listens on :4001 in dev

# 3. Run web frontend server (separate terminal, optional for web testing)
cd ansible_distribution_frontend
npm run dev                # listens on :5173 and proxies /api/* to :4001

# 4. Run Flutter app (separate terminal)
cd ansible_node/app
flutter run
```

### Subsequent builds

```bash
# Only needed when ansible_rust_core/src/api*.rs changes
./setup_codegen.sh

# App hot-reload works normally for Dart-only changes
```

## Key Design Decisions

**Progressive trust replaces passport-gated onboarding.** V1.x used a Groth16
ZKP over ePassport NFC data to prove "real human, unique identity". V2.0 moves
ordinary onboarding to app-held DID keys and progressive trust. Hardware-held
signing keys are still a known gap until platform-backed custody and explicit
reduced-trust mode are implemented.

**`did:elix` is the canonical identity; AT Protocol / `did:plc` is an opt-in
bridge.** Users are `did:elix` (domain-independent, self-certifying, portable
across relays), with a `did:key` wallet alias and `did:web` reserved for
issuers. The repo keeps XRPC primitives, but `did:plc` is now only an opt-in
Bluesky-bridge alias (its creation path retired; real DAG-CBOR genesis is
Phase D) — one bridge beside Nostr, ActivityPub, and Forum Host, never the
canonical identity. See the
[layered identity & `did:elix` method plan](docs/superpowers/plans/2026-06-16-layered-identity-did-method-plan.md).

**Forum Hosts own forum state.** Hosted boards, rules, moderation policy, and
distribution-facing forum state belong to a Forum Host. The current Phoenix
service co-locates Relay and Forum Host roles for MVP deployment, but the API
contract keeps the roles separate.

**Web sessions are app-mediated and cookie-backed.** The browser never receives
the root DID private key. App-approved web sessions use Relay-issued httpOnly
cookies, scoped grants, host audience checks, and explicit revocation.

**The AppView is the scalable read side.** `ansible_appview/phoenix` consumes the
relay op firehose, re-verifies signatures, and folds ops into a PostgreSQL read
model (feed items + follow graph). It serves the following/home feed so clients
never scan the global op stream — the key fix for relay egress at scale. It is a
**reproducible projection**: the read model and home timelines can be rebuilt from
the relay ops + follow graph, so caches are safe to flush. Full AT-style
multi-AppView federation and a standalone reputation labeler remain future work.
