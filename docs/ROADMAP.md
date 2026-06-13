# Ansible / Tris-Aura Roadmap

> **What this is:** the single master index of planning state for the Ansible
> (Tris-Aura Hybrid Network V2.0) repo — what is in flight, what is next, what
> is parked, and what already landed, with links to the underlying specs and
> plans.
>
> **Last updated:** 2026-06-12
>
> **Keep it current:** when a plan lands, is paused, or a new spec/plan is
> added under `docs/superpowers/`, update this file in the same change.
> Statuses below are based on plan checklists **and** git history — several
> completed plans never had their checkboxes ticked, so commits are the source
> of truth where they disagree.
>
> **Architecture sequencing:** the service-level phases (key custody →
> data-plane integrity → push distribution → federation completion →
> scale-out) live in the
> [service architecture plan](architecture/service_architecture_plan.md);
> "Phase N" references below point there.

## Product Track（產品線）

Product-priority view, parallel to the
[architecture phases](architecture/service_architecture_plan.md). Rationale:
the engineering foundation (identity/security/federation) is ahead of the
product loop — retention (notifications), safety (reporting/moderation), and
the flagship differentiator (trust-gated boards) are missing, and growth
surfaces (sharing/OG) have zero investment. PM review 2026-06-12.

### Add（新增）

| Item | Priority | Plan | Why |
|---|---|---|---|
| Notification system — in-app feed + badge first, content-free push second | P1 — **✅ Phase A + B pipeline shipped 2026-06-13** (only APNS/FCM credentials remain — config work) | [Plan](superpowers/plans/2026-06-12-notification-system.md) | Local projection over already-synced data (replies/follows/messages/moderation outcomes), feed + bell badge + settings; relay wake scheduler is debounced and strictly content-free (`{"hint":"sync"}`) |
| Content reporting + board moderation tools | P1 — **✅ shipped 2026-06-13** (incl. app tombstone/lock rendering) | [Plan](superpowers/plans/2026-06-12-content-reporting-moderation.md) | Reason-coded reports on both rails with tier-aware rate limits, web moderator console (queue/actions/audit), host-scoped tombstones + thread locks enforced at both write chokepoints and rendered web + app |
| Trust-gated boards（真人驗證版）| P1 — **✅ shipped 2026-06-13** | [Plan](superpowers/plans/2026-06-12-trust-gated-boards.md) | Highest ROI in the repo: the whole VC→tier pipeline existed, boards already had an empty `posting_policy` field — `min_post_tier` is now enforced relay-side and surfaced in app + web frontend |
| Cold-start strategy — genesis boards, default follows/subscriptions, seed content | P2 | (operations plan needed, not engineering) | Discover/feed are built but day-one network is empty; without seeding, launch = ghost town |
| Sharing & deep links — OG tags on frontend, share sheet + universal links in app | P2 | — | Verified absent (no OG tags, no share/deep-link). The natural forum growth channel (content → LINE/Threads → visit → register) is closed |
| Privacy-preserving product metrics (activation/retention, constitution-compatible) | P2 | — | Constitution restricts analytics, but without DAU/retention/board-activity aggregates every priority above is a guess; needs an explicit "constitutional measurement" design |

### Remove / Freeze（刪除或凍結）

| Item | Decision |
|---|---|
| AT Protocol / PLC bridge | **Freeze**: no further investment, remove from marketing surface; keep code as-is (removal costs more than keeping) |
| Extra app locales (de/es/fr/ja/ko/pt) | **Cut to zh-Hant + en**: maintenance liability — most screens bypass ARB via `uiCopy(zh:, en:)` anyway; re-add with real international users |
| Messenger expansion | **Contain**: 1:1 MVP stays, but no further scope (groups/media/read-receipts) — E2E messaging is a separate product and not this one's wedge |

### Improve（改善）

| Item | Notes |
|---|---|
| Value-prop copy: mechanism → benefit | Onboarding/marketing says「先建立身分」(engineer-speak); users need outcomes:「沒有機器人的討論區」「帳號和內容永遠是你的」 |
| Post-registration empty state | First session should guide: subscribe genesis boards, follow suggestions, first murmur — client half of the cold-start item |

## Now（進行中）

| Item | Priority | Links | Notes / dependencies |
|---|---|---|---|
| iOS staging release hardening — real Rust FFI bridge, relay auto-seed, DID auto-anchor, `elix.cool` rebrand, CI strict analyze | P1 | (no plan file; see recent `main` commits) | Current active work stream; consider capturing remaining iOS/TestFlight steps in a plan like the Android checklist |
| **Identity recovery & re-anchor design** — multi-device attestation, encrypted content-key backup, relay re-anchor protocol, anchor as user-signed portable object | P1 — launch blocker, **gates hardware custody** · **📝 design written 2026-06-13, awaiting review** | [Design](superpowers/plans/2026-06-13-identity-recovery-reanchor-design.md) · [Architecture plan — Phase 1.0](architecture/service_architecture_plan.md) | Proposed positions: D1 = dual-key (hardware P-256 device keys attest a backupable Ed25519 identity key), D5 = multi-device attestation + passphrase backup at launch, issuer-assisted later; self-certifying hash-chained anchor; recovery re-anchors get a 72h veto window with device alerts |
| Hardware-backed signing keys + explicit reduced-trust mode + rust `zeroize` | P1 — launch blocker | [Architecture plan — Phase 1](architecture/service_architecture_plan.md) · [Compliance review](superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md) | DID/PLC/Nostr keys still persist raw hex via `flutter_secure_storage`; needs Secure Enclave / StrongBox custody, no-export guarantee, reduced-trust fallback. Blocked by recovery design above |
| Cross-cutting foundations — app↔relay API versioning + observability baseline | P1 | [Architecture plan — Phase 0](architecture/service_architecture_plan.md) | Cheap now, expensive to retrofit: op schema versioning before Phase 2 evolves formats; metrics that later phase exit criteria depend on |

## Next（下一步）

| Item | Priority | Links | Notes / dependencies |
|---|---|---|---|
| TW provider **production** adapter (real TW FidO/MOICA partner API) | P1 | [Plan](superpowers/plans/2026-05-05-tw-provider-production-integration.md) · [Adapter boundary plan](superpowers/plans/2026-05-05-issuer-production-adapter-boundary.md) | Production-shaped flow + fail-closed boundary are done; the real partner integration is blocked on external partner API / trust-anchor details |
| MobileMoica RP production configuration | P1 | [Plan](superpowers/plans/2026-05-30-mobilemoica-rp-explicit-disclosure.md) · [Spec](superpowers/specs/2026-05-30-mobilemoica-rp-explicit-disclosure-design.md) | Flow implemented; production stays fail-closed until approval artifact IDs, MobileMoica service credentials, trust anchors, PKCS#7 validation, and revocation checks are configured |
| Android release readiness (beta build → Play Store) | P2 | [Plan](superpowers/plans/2026-05-10-android-release-readiness-checklist.md) | **In progress, stalled** — Task 1 (DID plugin packaging, build unblocked) done; identity/assets/signing, platform verification, and release checklist remain. Recent release effort has gone to iOS |
| External host compliance level — local persistence + policy use | P2 | [Architecture plan — Phase 1.4](architecture/service_architecture_plan.md) · [Compliance review](superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md) | Discovery exposes compliance labels already; local `ForumHost`/`RemoteNode` records don't persist them and ranking/sync/trust policy don't consume them yet |
| Data-plane integrity — AppView independent signature re-verification, relay `ops` partitioning + signed snapshots, relay internal schema separation (identity / forum / federation) | P2 | [Architecture plan — Phase 2](architecture/service_architecture_plan.md) | Needed before meaningful external traffic; AppView currently trusts relay ingest checks, the `ops` table is unbounded, and relay data groups need separable ownership before any future extraction |

## Later（未來）

| Item | Priority | Links | Notes / dependencies |
|---|---|---|---|
| Push distribution — op firehose over Phoenix Channels, Oban delivery workers, abuse-detection completion | P3 | [Architecture plan — Phase 3](architecture/service_architecture_plan.md) | After Phase 2 (snapshots make push restart-safe); replaces AppView polling and the Postgres retry loop |
| Federation completion — Nostr key custody, full ActivityPub inbox behaviors | P3 | [Architecture plan — Phase 4](architecture/service_architecture_plan.md) | Nostr custody depends on Phase 1; AP behaviors independent |
| DNS handle verification (DNS TXT + HTTPS `/.well-known`) | P3 | [Architecture plan — Phase 4.3](architecture/service_architecture_plan.md) | 🔜 future in component status; no spec/plan yet |
| Standalone Reputation Labeler service | P3 | [Architecture plan — Phase 4.4](architecture/service_architecture_plan.md) | Extract only when a second consumer exists (decision D3); VP→tier paths already propagate relay → AppView → app badges |
| LLM plugin / MCP agent access (ChatGPT, Claude, Codex, local MCP) | P3 | [TODO](superpowers/todos/2026-05-16-llm-plugin-mcp-access.md) | Backlog only — all phases unchecked. Should reuse app-mediated web-session grants; never exposes root DID keys |
| AI Agent (Component F) — summarisation/filtering over firehose | P4 | README component table | Explicitly P4; local AI-assistance foundation (providers, context packs, review flows) already landed via content lineage work |
| Multi-AppView federation / multi-region scale-out | P4 | [Architecture plan — Phase 5](architecture/service_architecture_plan.md) · [AppView design](superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md) | Single AppView is a reproducible projection today; multi-region (genesis target), cross-region transport (decision D2), and CDN/WAF land here |

## Parked（暫停）

| Item | Links | Why parked |
|---|---|---|
| zkID / OpenAC MOICA forum personhood path | [Plan](superpowers/plans/2026-05-30-zkid-moica-forum-personhood.md) | Explicitly **paused** in favor of the MobileMoica RP path; resume only if a true zkID/Mopro TW FidO binding becomes available with raw artifacts kept inside the local proving boundary |

## Done（已完成）

Ordered roughly by plan date. "Done" = MVP scope of the plan landed on `main`
(verified against commit history); partial/legacy caveats live in the README
component status table.

| Plan | Spec | Notes |
|---|---|---|
| [Follow users & boards](superpowers/plans/2026-05-04-follow-users-boards.md) | [design](superpowers/specs/2026-05-04-follow-users-boards-design.md) | Follow store, domain service, projector, inbox routing, UI (checklist not ticked; commits landed 05-04/05) |
| [TW digital identity VC wallet](superpowers/plans/2026-05-04-tw-digital-identity-vc-wallet.md) | — | Wallet foundation, Go issuer, VP verifier, presentation UI ("complete VC wallet Tasks 3-5" landed; mock provider later replaced) |
| [Issuer production adapter boundary](superpowers/plans/2026-05-05-issuer-production-adapter-boundary.md) | [design](superpowers/specs/2026-05-05-issuer-production-adapter-boundary-design.md) | Fail-closed without TW production adapter |
| [Shared credential wizard](superpowers/plans/2026-05-05-shared-credential-wizard.md) | [design](superpowers/specs/2026-05-05-shared-credential-wizard-design.md) | Multi-flow wizard embedded in Wallet |
| [TW provider app UX](superpowers/plans/2026-05-05-tw-provider-app-ux.md) | [design](superpowers/specs/2026-05-05-tw-provider-app-ux-design.md) | Wallet-first start/authorize/poll/issue flow |
| [TW provider production integration](superpowers/plans/2026-05-05-tw-provider-production-integration.md) | — | Stateful start/callback/status/issue API, replay rejection, no raw-assertion storage. Real partner adapter → see **Next** |
| [Content lineage, transformation & AI assistance](superpowers/plans/2026-05-06-content-lineage-transformation-ai.md) | [design](superpowers/specs/2026-05-06-content-lineage-transformation-design.md) · [TODO](superpowers/todos/2026-05-06-content-lineage-transformation-ai.md) | All TODO phases checked: murmur/note/discussion lineage, AI providers, review flows, public Lexicon sync |
| [TW provider operational hardening](superpowers/plans/2026-05-06-tw-provider-operational-hardening.md) | [design](superpowers/specs/2026-05-06-tw-provider-operational-hardening-design.md) | Session cleanup, audit-safe counters, health/readiness, deployment doc |
| [Federation implementation](superpowers/plans/2026-05-09-federation-implementation.md) | [strategy](superpowers/specs/2026-05-09-federation-strategy-design.md) | Publication outbox, app-side Nostr adapter, relay-side ActivityPub projection (80/81 boxes checked). Adapters remain "partial" per README |
| [Forum Host board model](superpowers/plans/2026-05-10-forum-host-board-implementation.md) | [design](superpowers/specs/2026-05-10-forum-host-board-design.md) | Forum-Host-owned hosted boards; UI copy superseded by 06-02 boundary work (see plan's alignment note) |
| [Mobile backup storage policy](superpowers/plans/2026-05-10-mobile-backup-storage-policy.md) | — | Backup-eligible canonical data vs no-backup remote mirror cache, iOS + Android |
| [App-mediated web session](superpowers/plans/2026-05-11-app-mediated-web-session.md) | [design](superpowers/specs/2026-05-11-app-mediated-web-session-design.md) · [TODO](superpowers/todos/2026-05-11-app-mediated-web-session.md) | All phases checked; bearer-token path superseded by httpOnly cookie hardening from boundary work |
| [Forum frontend IA / visual](superpowers/plans/2026-05-11-forum-frontend-ia-visual-implementation.md) | [design](superpowers/specs/2026-05-11-forum-frontend-ia-visual-design.md) · [web dev design](superpowers/specs/2026-05-11-web-development-design.md) | Renderers, app shell, Elix design system, frontend tests (checklist not ticked; commits landed) |
| [Encrypted messenger protocol](superpowers/plans/2026-05-14-encrypted-messenger-protocol.md) | [design](superpowers/specs/2026-05-14-encrypted-messenger-protocol-design.md) | 1:1 E2E messenger: Rust crypto facade, mailbox API, Postgres relay store, UI (checklist not ticked; commits landed) |
| [Messenger contact discovery](superpowers/plans/2026-05-14-messenger-contact-discovery.md) | [design](superpowers/specs/2026-05-14-messenger-contact-discovery-design.md) | Contact store, resolvers, availability endpoint, picker, requests/ID compose |
| [Passport wallet credential extension](superpowers/plans/2026-05-24-passport-wallet-credential-extension.md) | [design](superpowers/specs/2026-05-24-passport-wallet-credential-extension-design.md) | Passport NFC personhood, unified bindings, Data Integrity proofs, OID4VP QR presentation |
| [MobileMoica RP explicit disclosure](superpowers/plans/2026-05-30-mobilemoica-rp-explicit-disclosure.md) | [design](superpowers/specs/2026-05-30-mobilemoica-rp-explicit-disclosure-design.md) | Flow + broker boundary implemented; production config → see **Next** |
| [Relay / Forum Host boundary](superpowers/plans/2026-06-02-relay-forum-host-boundary-implementation.md) | [design](superpowers/specs/2026-06-02-relay-forum-host-boundary-design.md) | Durable forum host store, signed intents, discovery endpoints, cookie web sessions, compliance metadata (checklist not ticked; ~40 commits landed) |
| [Following feed — followed-author sync](superpowers/plans/2026-06-04-following-feed-author-sync.md) | [AppView design](superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md) | Followed-author op retention gate, unfollow purge |
| [Following feed — murmur/note timeline](superpowers/plans/2026-06-04-following-feed-murmur-note.md) | same as above | Public murmur/note as relay ops + timeline projector |
| [AppView Component D — Phase B](superpowers/plans/2026-06-05-appview-component-d-phase-b.md) | same as above | `ansible_appview/phoenix` ingest + timeline; **Phase C** (fan-out-on-write home timeline, follow-graph index, Redis) and discovery P1–P3 also landed |

Spec-only items that landed without a separate plan: the
[engineering constitution](superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md)
and the [full architecture diagram](superpowers/specs/2026-05-31-full-architecture-diagram-design.md).

## Known gaps & compliance debt（已知缺口）

Source: [constitution compliance review (2026-05-24)](superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md)
and the README component status table.

1. **Hardware-backed key custody + reduced-trust mode** — *not compliant yet;
   launch blocker.* Raw private key hex still persists via secure-storage-style
   APIs; some comments overclaim Secure Enclave/StrongBox semantics. Needs
   platform-backed signing keys, no raw-key export from self-custody paths, and
   an explicit reduced-trust mode. Affects DID, PLC, and Nostr key paths.
2. **External host compliance level** — *partially implemented.* Discovery
   exposes and the app displays compliance labels, but local host records do
   not persist `constitution_compliance`, and ranking/sync/recommendation/trust
   policy do not consume it.
3. **TW provider production adapter** — issuer fails closed in production by
   design until the real partner API / trust anchors are configured (same gap
   gates MobileMoica RP production).
4. **Standalone Reputation Labeler** — tier mapping exists inside the relay
   path only; no independent labeler service.
5. **DNS handle verification** — not started (🔜 future).
6. **AI Agent (Component F)** — not started (P4).
7. **Partial adapters** — Nostr production key custody incomplete; ActivityPub
   full federation behavior incomplete; AT Protocol/PLC genesis & local CID
   paths are compatibility stubs (see README component table).
8. Items the review **fixed** (Email OTP ≠ verified human; wallet parser
   rejects passport/personhood claims; mock provider no raw-assertion
   fallback) and **cleared as compliant** (passport binding, publication
   fail-closed, TW raw-data retention specs) are recorded in the review doc.

## How planning works here（規劃流程）

- **Specs** live in `docs/superpowers/specs/` — design documents
  (`YYYY-MM-DD-*-design.md`) plus the
  [engineering constitution](superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md)
  and its [compliance review](superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md).
- **Plans** live in `docs/superpowers/plans/` — task-by-task implementation
  plans with `- [ ]` checklists. Caveat: checklists are not always ticked when
  work lands, so cross-check git history before trusting an unchecked plan.
- **Constitution gate** (see [AGENTS.md](../AGENTS.md)): before any spec, plan,
  or implementation touching identity, storage, sync, verification,
  federation, moderation, ranking, governance, credentials, Wallet, Issuer,
  Relay, Forum Host, or AppView, read the constitution first; specs/plans must
  include a `Constitution Review` section (or state why it does not apply),
  and check the compliance review before claiming compliance.
- **TODOs / parked backlog** live in `docs/superpowers/todos/` — currently the
  two completed phase checklists linked above plus the parked
  [LLM plugin & MCP access](superpowers/todos/2026-05-16-llm-plugin-mcp-access.md) backlog.
