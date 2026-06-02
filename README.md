# Ansible — Tris-Aura Hybrid Network V2.0

A local-first, multi-protocol forum and identity stack. Participants are
pseudonymous but Sybil-resistant through layered trust: base-level accounts use
app-held DID keys, while higher trust tiers come from accepted credentials or
other explicit verification paths. AT Protocol / PLC is currently a
compatibility path, not the only public federation identity. Nostr publication,
Relay-side ActivityPub projection, Forum Host APIs, and app-mediated web
sessions exist as partial MVP slices.

## Architecture

```
ansible_node/app          Flutter mobile/desktop node — UI, local Repo, Passkeys auth
ansible_core/
  domain/                 Business logic, auth contracts, sync interfaces
  store/                  Drift (SQLite) — atproto Repo, MST, Op queue
  did/                    DID key management: did:plc / did:web (flutter_rust_bridge FFI)
  vc/                     Lexicon record models, MST engine (Rust FFI)
ansible_rust_core/        Rust crate — Ed25519, MST, Lexicon signing, atproto repo
ansible_relay/phoenix/    Elixir/Phoenix — co-located Relay, Forum Host, web sessions,
                          ActivityPub/XRPC compatibility, discovery APIs
ansible_distribution_frontend/
                          Node/static web frontend — Forum Host public views and
                          app-approved web-session flow
docs/
  protocol/               Sync spec v2.0, AT Protocol Lexicon conventions
  architecture/           Genesis hosting, deployment notes
  security/               SOSP pre-launch security policy
```

## Identity Flow (Current MVP)

```
User taps "建立帳號"
  → app creates/loads a local DID signing key
  → optional compatibility paths can create local-shaped did:plc / did:web context
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
| ActivityPub adapter | ✅ partial | Relay-side actor/WebFinger/outbox/projection/retry; full federation behavior remains incomplete |
| AT Protocol / PLC bridge | ✅ partial / legacy | XRPC `createRecord` and `resolveHandle`; PLC genesis/local CID paths are compatibility stubs |
| AppView Aggregator | 🔜 draft | No `ansible_appview/phoenix` package currently exists |
| DNS Handle verification | 🔜 future | DNS TXT + HTTPS /.well-known lookup |
| Reputation Labeler | ✅ partial | VP-to-tier paths exist; complete AppView labeler is missing |
| AI Agent Comp F | 🔜 P4 | Summarisation and filtering over Firehose stream |

## Social Graph Direction

Follow users and follow boards are implemented as a local-first social
subscription layer. User follows build a Following feed from accepted actor
relationships. Board follows build the same feed from accepted board
relationships and remote board follows toggle `BoardSyncConfig`.

Follow data must not contain Wallet credential payloads or Taiwan digital
identity assertions.

## TW Provider Issuance Direction

The issuer supports a production-shaped TW provider flow with single-use auth
state, replay rejection, provider proof verification boundaries, and holder-bound
credential issuance after callback verification. Raw provider assertions and
government identity fields stay inside the issuer boundary and must not be
logged or stored.

## Getting Started

### Prerequisites

```bash
# Rust toolchain
curl https://sh.rustup.rs -sSf | sh

# Flutter SDK ≥ 3.10 on PATH
# Elixir ≥ 1.16 + Erlang/OTP 26+ on PATH
# PostgreSQL running locally
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

**AT Protocol / PLC is a compatibility context.** The repo has XRPC and PLC
primitives, but current federation direction keeps local data canonical and
treats AT/PLC as one bridge beside Nostr, ActivityPub, and Forum Host.

**Forum Hosts own forum state.** Hosted boards, rules, moderation policy, and
distribution-facing forum state belong to a Forum Host. The current Phoenix
service co-locates Relay and Forum Host roles for MVP deployment, but the API
contract keeps the roles separate.

**Web sessions are app-mediated and cookie-backed.** The browser never receives
the root DID private key. App-approved web sessions use Relay-issued httpOnly
cookies, scoped grants, host audience checks, and explicit revocation.

**AppView remains future work.** Do not treat the current repository as having a
complete Phoenix AppView aggregator, Firehose pipeline, or PostgreSQL index.
