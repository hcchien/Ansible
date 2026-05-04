# Ansible - Tris-Aura Headless Forum Stack

Ansible is the local-first Tris-Aura forum stack. It ships domain logic,
storage, sync handlers, relay deployment, and Flutter UI surfaces inside one
Dart/Flutter monorepo.

The current identity direction is layered:

- basic accounts use app-held DID keys;
- higher trust tiers are granted through Verifiable Credentials;
- ePassport NFC/MRZ/BAC/PACE is not the planned production proofing path;
- Taiwan digital identity proofing, through an approved natural person
  certificate / TW FidO / MOICA flow, is the intended source for Tris-Aura's own
  `Verified Human` credential.

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
  - `protocol/tris_aura_vc_wallet_spec_v0.1.md`: internal VC Wallet protocol
  - `architecture/tw_digital_identity_vc_wallet.md`: Taiwan digital identity and Wallet architecture
  - `superpowers/specs/2026-05-04-follow-users-boards-design.md`: follow users and boards design spec
  - `superpowers/plans/2026-05-04-tw-digital-identity-vc-wallet.md`: implementation plan
  - `superpowers/plans/2026-05-04-follow-users-boards.md`: follow users and boards implementation plan

## Identity And Wallet Direction

The App needs Wallet capability because Tris-Aura will issue its own VCs instead
of embedding government identity into forum records. The first credential type is
`TrisAuraHumanityCredential`, which proves that a holder DID completed approved
Taiwan natural-person-certificate identity proofing without disclosing national
ID, legal name, birth date, address, certificate serial, phone, or email.

`TrisAuraHumanityCredential` is not self-issued by users. The App only requests,
stores, and presents it. Issuance belongs to the Tris-Aura Issuer server after it
verifies the approved Taiwan digital identity proofing result and holder DID
control.

Open review items are tracked in
[`docs/architecture/tw_digital_identity_vc_wallet.md`](docs/architecture/tw_digital_identity_vc_wallet.md).
They must be resolved with official integration documentation before production
identity proofing is enabled. Until then, implementation should use deterministic
fixtures and a mock identity-provider adapter.

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
