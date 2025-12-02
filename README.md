# Ansible - Headless Forum Stack

Ansible is a local-first forum stack that ships domain logic, storage, sync handlers, relay deployment, and UI surfaces inside one Dart/Flutter monorepo.

## Structure

- `ansible_core/`
  - `domain/`: business logic, auth, sync contracts
  - `store/`: Drift entities, repositories, and projections
  - `ap/`, `did/`, `vc/`: ActivityPub, DID, and VC helpers
  - `tooling/analyzer/`: architecture lint rules
- `ansible_sync/`
  - `handlers/`: Shelf `/inbox` + `/sync/delta` controllers with tests
- `ansible_relay/`
  - `server/`: deployment-facing binary that wires storage + sync handlers
- `ansible_node/`
  - `app/`: Flutter desktop/mobile/web local node UI
  - `web_ui/`: legacy web-focused UI
- `ansible_cli/`
  - `scripts/`: helper scripts for builds and local dev
- `docs/`
  - `protocol/ansible_sync_spec_v0.1.md`: evolving sync protocol

## Getting Started

### Prerequisites
- Flutter SDK
- Dart SDK

### Running Local Node
```bash
./ansible_cli/scripts/dev_local.sh
```

### Running Relay API
```bash
./ansible_cli/scripts/dev_relay.sh
```
