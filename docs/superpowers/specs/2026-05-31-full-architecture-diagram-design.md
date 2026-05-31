# Full Architecture Diagram Design

> Status: Approved for implementation planning  
> Date: 2026-05-31  
> Scope: Tris-Aura architecture documentation for App, Wallet, Issuer, Relay,
> Forum Host, Web/AppView, federation adapters, external providers, and current
> compliance gaps

## Goal

Create a complete architecture diagram that explains Tris-Aura's target system
without hiding the mixed maturity of the current repo. The diagram must be
useful as a maintainer-facing reference, a review artifact for future specs, and
a quick onboarding map for contributors who need to understand how the app,
relay, issuer, web frontend, Forum Host, and federation paths fit together.

The diagram is a documentation artifact, not a runtime dashboard.

## Design Decision

Use a static HTML page with an inline SVG layered architecture map.

The primary map shows the target architecture, while node and edge labels show
implementation maturity:

- `implemented`: component or path has concrete repo implementation.
- `partial`: an MVP or slice exists in the repo, but the component or path is
  not complete enough to describe as production-ready.
- `draft`: component or path is described in approved or active design docs but
  is not complete.
- `planned`: future direction described by specs or roadmap docs.
- `legacy`: compatibility path that remains relevant but is no longer the only
  long-term direction.
- `gap`: known compliance or launch blocker.
- `external`: provider or network outside first-party control.

Nodes may carry more than one chip when implementation maturity and product
role differ. For example, AT Protocol / PLC is both `partial` and `legacy`
because a compatibility slice exists, but it is no longer the sole long-term
federation direction.

This hybrid model avoids two misleading extremes: a pure current-state diagram
that omits important architectural direction, and a pure target-state diagram
that makes draft systems look finished.

## Artifact

Create:

```text
docs/architecture/full_system_architecture.html
```

The file must be self-contained:

- inline SVG for the diagram;
- inline CSS;
- no CDN dependency;
- no build step;
- no remote JavaScript;
- usable directly from a browser or a static docs host.

SVG is preferred over a D3 force graph for the canonical document because a
stable hand-laid diagram is easier to review in pull requests and less likely to
change layout unpredictably. Small JavaScript interactions may be added if they
remain self-contained and deterministic, but the diagram must still be readable
without interaction.

## Diagram Structure

The map is organized by trust and ownership boundary:

1. User-controlled boundary
   - Elix / Ansible App
   - Local Store / Repo
   - Wallet
   - Rust Core / Signing
   - App-mediated approval for web sessions

2. First-party service boundary
   - Issuer
   - Relay / Distribution Server
   - Forum Host
   - Reputation Labeler
   - Opaque Messenger Transport

3. Public Web / AppView boundary
   - Web Frontend
   - AppView / Public Views
   - Web Session Token

4. External / federation systems
   - TW Provider / MOICA
   - Nostr Relays
   - ActivityPub Network
   - AT Protocol / PLC Bridge
   - External Forum Hosts

The visual hierarchy should make boundaries more important than individual
implementation packages. Package names may appear in details or source notes,
but the main diagram should use product/system terms.

ActivityPub must be labeled as `partial`, not `planned`: the relay has an
implemented MVP for ActivityPub actor discovery, WebFinger, inbox/outbox
endpoints, publication intent projection, Create/Update/Delete mapping, delivery
attempt storage, and retry state. The label remains `partial` because full
production federation behavior is still broader than this slice.

Nostr must be labeled as `partial`, not `planned`: the app has an implemented
MVP for direct relay publication, Nostr relay settings, NIP-01 event envelopes,
BIP-340/Schnorr signing, NIP-23 long-form note projection, NIP-09 deletes,
NIP-02 follow projection, NIP-19 identifiers, and NIP-65 relay list metadata.
The label remains `partial` because production key custody and broader relay
operations are not complete.

AT Protocol / PLC must be labeled as `partial` plus `legacy`: the repo has
XRPC `createRecord` / `resolveHandle` endpoints, Lexicon record validation,
Ed25519 signature verification, Rust AT Protocol primitives for DAG-CBOR, CID,
commit signing, and `did:plc` genesis operation creation. It remains `legacy`
in the diagram because the current federation direction treats AT Protocol as a
compatibility context rather than the only public federation identity path.

## Required Flows

The map must show these flows:

- App writes local private content and projections to local store.
- App and Wallet request credential offers and receive holder-bound VCs from
  the Issuer.
- Issuer interacts with approved external proofing providers while keeping raw
  legal identity inside the Issuer boundary.
- Wallet presents VPs only after explicit user consent.
- App creates signed publication intents for public or unlisted distribution.
- Forum Host owns hosted boards, threads, posts, permissions, moderation, and
  distribution-facing forum state.
- Web Frontend reads public views and can participate through hosted web
  accounts or app-mediated self-custody DID sessions.
- App-mediated web login grants scoped browser sessions without exporting root
  DID private keys to the browser.
- App may publish selected public content directly to Nostr relays through the
  implemented MVP Nostr adapter, while the diagram marks the adapter as partial
  until production key custody and broader relay operations are complete.
- Relay distributes ActivityPub server-to-server activities through the
  implemented MVP ActivityPub adapter, while the diagram marks the adapter as
  partial until production-grade federation behavior is complete.
- AT Protocol / PLC remains a partially implemented compatibility context, not
  the only long-term public federation identity path.
- External Forum Hosts must expose or carry a visible constitution compliance
  level before first-party ranking, recommendation, sync, or trust policy relies
  on their behavior.

## Status Labels

Every node must have a status chip. Key edges must also communicate state:

- solid edge: current or core expected path;
- dashed edge: partial, draft, planned, or legacy path;
- red or warning treatment: legacy path or compliance gap;
- neutral external treatment: external provider or network.

The HTML must include a visible legend defining status terms. The legend should
not require hovering or clicking to understand the diagram.

## Source Notes

The page should include source links to the documents that define the diagram:

- `README.md`
- `docs/architecture/genesis_hosting.md`
- `docs/architecture/tw_digital_identity_vc_wallet.md`
- `docs/architecture/tw_provider_production_integration.md`
- `docs/protocol/tris_aura_sync_spec_v2.0.md`
- `docs/protocol/tris_aura_federation_strategy_v0.1.md`
- `docs/protocol/tris_aura_vc_wallet_spec_v0.1.md`
- `docs/superpowers/plans/2026-05-09-federation-implementation.md`
- `docs/superpowers/specs/2026-05-10-forum-host-board-design.md`
- `docs/superpowers/specs/2026-05-11-app-mediated-web-session-design.md`
- `docs/superpowers/specs/2026-05-11-web-development-design.md`
- `docs/superpowers/specs/2026-05-14-encrypted-messenger-protocol-design.md`
- `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
- `docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`

## Constitution Review

This documentation touches identity, storage, sync, verification, federation,
moderation, ranking, community governance, Wallet, Issuer, Relay, Forum Host,
and AppView behavior. The constitution applies.

The diagram must preserve these constitution constraints:

- Local-first private content remains inside the user-controlled app boundary.
- Private content must not be shown as flowing to relays, Forum Hosts, AppView,
  external hosts, federation networks, logs, analytics, or AI services.
- Wallet credential presentation requires explicit user consent.
- Issuer proofing may process provider results only inside the Issuer boundary.
- Raw legal identity, provider assertions, private keys, and biometric material
  must not appear in Relay, Forum Host, AppView, federation payloads, public
  credentials, normal verifier presentations, or logs.
- Duplicate-prevention commitments are Issuer-bound enforcement artifacts and
  must not be shown as public credential claims or normal presentation fields.
- Web sessions must be scoped, short-lived, revocable, and must not imply that
  browser storage contains root DID private keys.
- Forum Host moderation must be shown as host-level governance, not universal
  global truth.
- External Forum Hosts must surface compliance level as a current gap before
  their behavior affects first-party ranking, recommendation, sync, or trust
  decisions.

The current compliance review identifies two remaining gaps that the diagram
must not hide:

- hardware-backed key storage and reduced-trust mode are not complete;
- external host constitution compliance level is not implemented.

The diagram is constitution-compliant only if those gaps are explicitly labeled
and if raw identity/private content flows remain absent from public and
federated paths.

## Implementation Notes

The final HTML should use accessible text and stable layout:

- `role="img"` and a useful `aria-label` on the SVG;
- readable labels at normal desktop widths;
- horizontal scroll fallback for small screens rather than overlapping text;
- high-contrast status colors plus text labels, not color-only meaning;
- a short written summary below the SVG for readers who do not parse diagrams
  easily.

The first implementation does not need full D3 interactivity. A future
interactive version may add filters for status or flow type if the static map
proves too dense.

## Acceptance Criteria

- `docs/architecture/full_system_architecture.html` exists and opens directly
  in a browser.
- The page contains a complete layered SVG map covering App, Wallet, Issuer,
  Relay, Forum Host, Web/AppView, federation networks, external providers, and
  external host compliance.
- All major nodes have visible status labels.
- Partial, draft, planned, legacy, and gap paths are visually distinguishable.
- Constitution guardrails are visible on the page.
- Source document links are included.
- No remote assets, CDN scripts, or build step are required.
