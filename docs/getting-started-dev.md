# Getting Started — Developer Onboarding

A practical guide to building and running the Ansible / Tris-Aura stack locally.
Every command below is taken from the component READMEs, config files, and
`setup_codegen.sh` in this repo. For the system overview, read the root
[`README.md`](../README.md) first.

## Prerequisites

| Toolchain | Version | Used by | Source of truth |
|---|---|---|---|
| Flutter SDK | 3.38.3 (stable; CI pin), Dart SDK `^3.10.0` | `ansible_node/app`, `ansible_core/*` | `.github/workflows/flutter-ci.yml`, `ansible_node/app/pubspec.yaml` |
| Rust (rustup/cargo) | stable | `ansible_rust_core`, relay's `sig_verifier_nif` NIF | `setup_codegen.sh` |
| flutter_rust_bridge_codegen | 2.7.0 preferred (2.4.0 fallback) | Dart↔Rust FFI codegen | `setup_codegen.sh` |
| Elixir / Erlang | Elixir `~> 1.19`, OTP ≥ 27 | `ansible_relay/phoenix`, `ansible_appview/phoenix` | each `mix.exs`; Docker images pin 1.19.0 / OTP 27.2 |
| Go | ≥ 1.25 | `ansible_issuer/go` | `go.mod` (`go 1.25.0`) |
| Node | ≥ 22 (stdlib only, no npm deps) | `ansible_distribution_frontend` | frontend README; Docker `node:22-alpine` |
| PostgreSQL | local server on `:5432` | relay, appview, issuer (optional) | `config/dev.exs` / `config/test.exs` |

```bash
# Rust
curl https://sh.rustup.rs -sSf | sh
```

## One-Time Setup

```bash
git clone <repo-url> Ansible && cd Ansible
./setup_codegen.sh
```

`setup_codegen.sh` does, in order:

1. Checks `cargo`, `flutter`, `dart`, and installs `flutter_rust_bridge_codegen`
   if missing.
2. Builds `ansible_rust_core` (debug + release).
3. Runs `flutter_rust_bridge_codegen generate` over `crate::api`,
   `crate::api_atproto`, `crate::api_zkp`, `crate::api_crdt`,
   `crate::api_messenger`, emitting Dart bindings into
   `ansible_core/did/lib/src/rust/` and a C header into
   `ansible_core/did/ios/Classes/`.
4. Runs Drift `build_runner` in `ansible_core/store`.
5. Runs `flutter pub get` across `ansible_core/{domain,store,did,vc}` and
   `ansible_node/app`.

Flags: `--test` also runs all Dart + Rust tests; `--clean` runs `cargo clean` +
`build_runner clean` first. Re-run the script whenever
`ansible_rust_core/src/api*.rs` or a Drift schema changes; Dart-only changes
just hot-reload.

**Common failure — frb codegen version.** frb 2.4.0 has a `--dart-output`
path-handling bug (it `mkdir`s `frb_generated.dart` and fails with
`File exists`), and both 2.4.x and 2.7.x hit a transitive `indicatif` dependency
conflict unless installed with `--locked`. The script handles this by trying, in
order: `cargo install flutter_rust_bridge_codegen --version 2.7.0 --locked`,
then `2.4.0 --locked`, then latest `--locked`. If you already have a broken
2.4.x install, the script force-upgrades to 2.7.0. The Dart package pin lives in
`ansible_core/did/pubspec.yaml`.

### Databases

Dev configs (`config/dev.exs`) connect as `username: $USER` (fallback
`postgres`) with an **empty password** on `localhost`:

```bash
# Relay + AppView dev DBs (created by mix ecto.create, shown for reference):
#   ansible_relay_dev, ansible_appview_dev
cd ansible_relay/phoenix   && mix deps.get && mix ecto.create && mix ecto.migrate
cd ansible_appview/phoenix && mix deps.get && mix ecto.create && mix ecto.migrate

# Issuer: no DB needed in MOCK_MODE. For the optional Postgres-backed tests:
createdb ansible_issuer_test
```

Test DBs (`config/test.exs`) are `ansible_relay_test` / `ansible_appview_test`
and read `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_DB` (defaults `postgres`/`postgres`/`localhost`/`5432`).

## Running the Stack Locally

### Minimal path: app + relay

The relay is the only service the app needs for sync. On first run with an
empty node list, the app **auto-seeds a default relay node** from
`ANSIBLE_RELAY_BASE_URL` (default `http://127.0.0.1:4001`), so a fresh install
syncs without manually adding a relay in Sync settings (see
`HomeShell._ensureDefaultRelayNode` in
`ansible_node/app/lib/screens/home_shell.dart`).

```bash
# Terminal 1 — relay on :4001
cd ansible_relay/phoenix && mix run --no-halt

# Terminal 2 — app (defaults already point at 127.0.0.1:4001)
cd ansible_node/app && flutter run -d macos   # or linux/windows/web
```

Override endpoints with dart-defines when needed:

```bash
flutter run -d macos \
  --dart-define=ANSIBLE_APP_ENV=dev \
  --dart-define=ANSIBLE_RELAY_BASE_URL=http://127.0.0.1:4001 \
  --dart-define=ANSIBLE_ISSUER_BASE_URL=http://localhost:4002 \
  --dart-define=ANSIBLE_ATPROTO_BASE_URL=http://127.0.0.1:4001
```

### Full path

One command: `make dev` (= `docker compose up --build`) starts postgres + all
four services with the host ports below — see
[`docker-compose.yml`](../docker-compose.yml). To run natively instead:

Start order: **postgres → relay → appview → issuer → frontend** (appview polls
the relay; the frontend proxies `/api/*` to the relay).

| # | Service | Command (from its directory) | Dev port |
|---|---|---|---|
| 1 | PostgreSQL | (your local server) | 5432 |
| 2 | Relay / Forum Host | `cd ansible_relay/phoenix && mix run --no-halt` | 4001 |
| 3 | AppView | `cd ansible_appview/phoenix && mix run --no-halt` | 4003 (polls `RELAY_BASE_URL`, default `http://localhost:4001`) |
| 4 | Issuer (mock mode) | see below | 4002 (`PORT` overrides) |
| 5 | Distribution frontend | `cd ansible_distribution_frontend && npm run dev` | 5173 (proxies `/api/*` to `RELAY_BASE_URL`, default `http://localhost:4001`) |

Issuer in mock mode (no DB, no real provider):

```bash
cd ansible_issuer/go
MOCK_MODE=true \
ISSUER_DID=did:web:issuer.localhost \
ISSUER_URL=http://localhost:4002 \
ISSUER_PRIVATE_KEY_HEX=$(openssl rand -hex 32) \
SUBJECT_COMMITMENT_PEPPER=$(openssl rand -hex 32) \
go run ./cmd/server
```

Note on Docker images: all four service Dockerfiles expose/serve on **8080**
(not the dev ports), and the frontend image binds `HOST=0.0.0.0`. Dev ports
above come from `config/dev.exs` (relay/appview), the issuer default `PORT`,
and the frontend server default.

## Running Tests

`make test` runs every suite; `make help` lists per-component targets
(`test-app`, `test-relay`, `test-issuer`, ...). Raw commands:

```bash
# Dart/Flutter — per package, or all at once via the script
cd ansible_node/app && flutter test        # same for ansible_core/{domain,store,did,vc}
./setup_codegen.sh --test                  # all Dart packages + Rust

# Rust
cd ansible_rust_core && cargo test

# Relay (needs Postgres; test DB ansible_relay_test)
cd ansible_relay/phoenix
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.create
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.migrate
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix test

# AppView (test DB ansible_appview_test) — same pattern
cd ansible_appview/phoenix
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.create
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.migrate
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix test

# Issuer
cd ansible_issuer/go
go build ./... && go vet ./... && go test ./...   # Postgres-backed tests skip
ISSUER_TEST_DATABASE_URL="postgres://$USER@localhost:5432/ansible_issuer_test" go test ./...

# Frontend
cd ansible_distribution_frontend && npm test
```

## Common Pitfalls

- **frb codegen version conflict.** See One-Time Setup above: use 2.7.0
  `--locked`; 2.4.0 has the `--dart-output` EEXIST bug and the `indicatif`
  conflict bites without `--locked`.
- **iOS Rust bridge / Xcode clang probe hang.** With Xcode 26.5, iOS release
  builds can stall after `Running Xcode build...` on a SwiftBuildService
  `clang -v -E -dM ... -c /dev/null` metadata probe blocked in `write()`. Use
  `ansible_node/app/scripts/install_ios_staging_release.sh
  --watchdog-clang-probe`, which kills only the stuck probe. Standalone iOS
  staging installs must go through that script (`flutter run --release` with
  dart-defines, incl. `ANSIBLE_USES_REAL_RUST_BRIDGE=true`) — `flutter install`
  can't pass dart-defines, and a bundle without them boots as
  `ANSIBLE_APP_ENV=dev` and fails readiness before `runApp()`.
- **Postgres auth.** Dev configs use your OS username (`$USER`) with an empty
  password; test configs default to `postgres`/`postgres` unless you pass
  `POSTGRES_USER`/`POSTGRES_PASSWORD`. If `mix ecto.create` fails with an auth
  error, match these to your local Postgres setup (e.g. a Homebrew install
  trusts `$USER` with no password; a Docker Postgres usually wants
  `postgres`/`postgres`).
- **Prod env fails fast.** With `ANSIBLE_APP_ENV=prod`, the app refuses to start
  if relay/issuer/atproto endpoints are local or insecure, or if the insecure
  identity/signing fallbacks are enabled.

## Deeper Docs

- [`docs/ROADMAP.md`](ROADMAP.md) — master planning index (now / next / parked / done, known gaps)
- [`docs/deployment/cloud_run_deploy.md`](deployment/cloud_run_deploy.md) — full Cloud Run deploy runbook (relay §, issuer §7, frontend §8, appview §8a)
- [`docs/deployment/scaling_operations.md`](deployment/scaling_operations.md) — scaling flags and operations
- [`docs/deployment/tw_provider_issuer_deployment.md`](deployment/tw_provider_issuer_deployment.md) — TW provider / MobileMoica issuer env
- [`AGENTS.md`](../AGENTS.md) — **constitution gate**: before changing identity, storage, sync, verification, federation, moderation, ranking, credentials, Wallet, Issuer, Relay, Forum Host, or AppView behavior, read `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md` and the compliance review
