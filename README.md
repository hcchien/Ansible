# Ansible — Tris-Aura Hybrid Network V2.0

A decentralised, AT Protocol-native P2P forum. Participants are pseudonymous but
Sybil-resistant through a layered reputation system: base-level accounts are
created with Passkeys (no password, no passport required), while higher trust
tiers are earned through DNS Handle ownership or optional out-of-band identity
verification.

## Architecture

```
ansible_node/app          Flutter mobile/desktop node — UI, local Repo, Passkeys auth
ansible_core/
  domain/                 Business logic, auth contracts, sync interfaces
  store/                  Drift (SQLite) — atproto Repo, MST, Op queue
  did/                    DID key management: did:plc / did:web (flutter_rust_bridge FFI)
  vc/                     Lexicon record models, MST engine (Rust FFI)
ansible_rust_core/        Rust crate — Ed25519, MST, Lexicon signing, atproto repo
ansible_relay/phoenix/    Elixir/Phoenix — Firehose relay, Lexicon filter, Op ingestion
ansible_appview/phoenix/  Elixir/Phoenix — AppView aggregator, PostgreSQL index, LiveView
docs/
  protocol/               Sync spec v2.0, AT Protocol Lexicon conventions
  architecture/           Genesis hosting, deployment notes
  security/               SOSP pre-launch security policy
```

## Identity Flow (Passkeys + AT Protocol)

```
User taps "建立帳號"
  → Passkeys (WebAuthn) generates Ed25519 keypair via Secure Enclave / StrongBox
  → did:plc registration through PLC directory server
  → App receives a default Handle: @user.trisaura.io
  → Optional: user points DNS TXT / HTTPS /.well-known/atproto-did to upgrade Handle
  → Relay marks DID as "Active"; Reputation Labeler tier = Basic
```

## Post Flow (MST Sync)

```
User composes a post
  → App creates a Lexicon record (io.trisaura.post) signed by DID
  → Record written into local MST Repo (SQLite)
  → Incremental Repo commit pushed to Firehose Relay (Comp C)
  → AppView (Comp D) picks up Firehose stream, indexes into PostgreSQL
  → Web forum and other App subscribers receive the update
```

## Component Status

| Component | Status | Notes |
|---|---|---|
| Ed25519 DID — did:key stub | 🔄 Migrating | Rust via flutter_rust_bridge → replacing with did:plc in P1 |
| Passkeys (WebAuthn) login | 🔜 P1 | Replace ZKP anchor flow |
| did:plc registration | 🔜 P1 | Via PLC directory; did:web for custom domains |
| MST Repo engine (Rust) | 🔜 P1 | Replaces raw Yrs CRDT; atproto-compatible |
| Lexicon record signing | 🔜 P1 | io.trisaura.* namespace |
| Elixir Firehose Relay | 🔜 P2 | WebSocket Firehose; replaces raw Gossipsub Op relay |
| AppView Aggregator | 🔜 P2 | PostgreSQL index + Phoenix LiveView |
| DNS Handle verification | 🔜 P3 | DNS TXT + HTTPS /.well-known lookup |
| Reputation Labeler | 🔜 P3 | Basic / DNS-verified / Verified Human tiers |
| AI Agent Comp F | 🔜 P4 | Summarisation and filtering over Firehose stream |

## Social Graph Direction

Follow users and follow boards are implemented as a local-first social
subscription layer. User follows build a Following feed from accepted actor
relationships. Board follows build the same feed from accepted board
relationships and remote board follows toggle `BoardSyncConfig`.

Follow data must not contain Wallet credential payloads or Taiwan digital
identity assertions.

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

# 2. Start Elixir Firehose Relay
cd ansible_relay/phoenix
mix deps.get && mix ecto.create && mix ecto.migrate
mix run --no-halt          # listens on :4001 in dev

# 3. Run Flutter app (separate terminal)
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

**Passkeys replace ZKP anchoring.** V1.x used a Groth16 ZKP over ePassport NFC
data to prove "real human, unique identity". V2.0 replaces this with Passkeys
(WebAuthn) stored in Secure Enclave / StrongBox. Sybil resistance is now handled
by a layered Reputation Labeler: DNS Handle verification and optional out-of-band
"Verified Human" attestation provide progressive trust, rather than a binary
passport gate.

**AT Protocol DID (did:plc / did:web) replaces did:key.** did:plc allows key
rotation and delegation through the PLC directory. did:web allows organisations
and power users to self-host their DID document via DNS.

**MST (Merkle Search Tree) replaces raw Yrs CRDT Ops.** Each user's content is
organised in an atproto-compatible Repo. Incremental commits are pushed as signed
MST deltas, enabling efficient P2P sync and independent verification.

**Firehose Relay replaces custom Gossipsub Op relay.** The Elixir relay subscribes
to the global atproto Firehose and filters records tagged with the
`io.trisaura.*` Lexicon namespace, then forwards them to the AppView aggregator.

**Relay is centralised for V2.0 Alpha.** Full P2P Firehose federation arrives in
P3. Until then the Genesis Firehose Relay is the single trust anchor for Op
ingestion.
