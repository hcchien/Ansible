# Community Notes Implementation Plan

> Status: implementation in progress
> Date: 2026-08-29
> Scope: native public Elix content, Relay, first-party Forum Host, AppView,
> Flutter, and the distribution frontend

## Goal

Add community-authored context to public Elix content without creating a
central fact-checking authority. A user can publish a signed context note with
sources, eligible community members can privately rate its usefulness, and a
Forum Host can publish a transparent, versioned aggregate status. App and web
clients show the status as host-scoped context, never as universal truth and
never as an automatic removal or global ranking penalty.

The user-visible feature name is **Community Notes / 社群脈絡**. The protocol
entity name is `context_note` so it cannot be confused with Elix's existing
long-form `note` entity.

## Non-goals

- No global misinformation label or automatic content removal.
- No global feed downranking based on a context-note result.
- No raw legal identity, credential claim, personhood commitment, or public
  rating history.
- No AI-generated rating. AI assistance may be added later for drafting or
  source checking, but human ratings remain authoritative.
- No external/federated targets until host compliance level is persisted and
  consumed by local ranking/trust policy.
- No claim of "cross-perspective consensus" until the dataset supports a
  calibrated bridging model.

## Constitution Review

The constitution applies because this feature touches identity, storage, sync,
verification, moderation, ranking, and community governance.

1. **Identity or credential:** note authors use their user-controlled DID to
   sign public `context_note` ops. Raters sign a Forum Host intent. The host
   exposes only a host-scoped opaque rater key and aggregate counts; it never
   exposes the rater DID on public APIs.
2. **Data leaving the device:** publishing a note explicitly sends its body,
   sources, target revision, and author DID to Relay. Rating explicitly sends
   the selected helpfulness level and reason tags to the chosen Forum Host.
   The rating UI states that the host receives the signed rating while the
   public sees only aggregates.
3. **Minimum claim:** anchored-DID validity and the existing reputation tier
   are sufficient. `verified_human` is used only to satisfy a cheaper quorum;
   once a quorum is met, each eligible rating has equal scoring weight.
4. **Raw identity exclusion:** legal name, passport data, national ID,
   provider assertions, biometrics, private keys, and personhood commitments
   are forbidden from note, rating, status, logs, and federation payloads.
5. **Ranking/moderation effects:** status decisions carry explicit reason
   codes, scorer id, scorer version, counts, and an input commitment. They only
   control the Community Notes card. They do not remove or globally downrank
   target content. Host moderation of an abusive note remains a separate,
   reason-coded action.
6. **Personhood binding:** the feature creates no new personhood binding. The
   existing private duplicate-prevention binding may affect the existing trust
   tier but is never copied into Community Notes records or presentations.
7. **Exit and reversibility:** authors may update or withdraw their notes;
   raters may replace their active rating; users may hide Community Notes;
   boards may disable the feature; and users may leave or choose another host.
8. **External hosts:** V1 accepts native content scored by a first-party Forum
   Host only. Federation remains disabled until the compliance persistence and
   policy-consumption gap is closed.

**Verdict:** constitution-compliant when the public/private split, host scope,
reason-coded decisions, equal vote weight after quorum, and no automatic
downranking/removal rules remain mandatory.

## Privacy And Trust Boundary

### Public

- Signed context-note op and its author DID.
- Target entity/revision reference and target content hash.
- Note body and source links.
- Aggregate rating counts and top explanation tags.
- Status, scorer id/version, decision reasons, evaluation time, and input hash.
- Host-scoped opaque contributor id when a stable public identifier is needed.

### Forum Host private

- Rater DID and signed rating intent.
- Host-scoped HMAC rater key.
- Individual helpfulness level and tags.
- Abuse/rate-limit events.

### Forbidden

- Public rater DID or a cross-host stable rater identifier.
- Raw identity/credential/personhood fields.
- IP/device fingerprint as a scoring feature.
- Political, demographic, nationality, or cultural labels used as viewpoint
  features.

## Protocol And Data Model

### `context_note` op

`context_note` is a normal DID-signed Relay op and supports `insert`, `update`,
and `delete`. Only the original author, including a constitution-compliant DID
migration alias, may update or delete it.

Required insert/update payload:

```json
{
  "targetEntityType": "murmur|note|thread|post",
  "targetEntityId": "entity-id",
  "targetOpId": "exact-signed-revision-op-id",
  "targetContentHash": "sha256:<lowercase-hex>",
  "boardId": "optional-hosted-board-id",
  "body": "concise contextual explanation",
  "sources": [
    {"url": "https://example.test/source", "title": "optional title"}
  ],
  "visibility": "public",
  "createdAt": "RFC3339"
}
```

Limits:

- body: 1..1,000 Unicode code units;
- sources: 1..5 HTTP(S) URLs;
- source title: at most 200 Unicode code units;
- target must exist in Relay and match entity type/id/op id;
- note author cannot rate their own note;
- private, followers-only, or encrypted targets are rejected;
- a context note is never a reply or ordinary feed item.

### Rating intent

Type: `io.trisaura.forum.rateContextNote`, version `1`, action
`rate_context_note`.

Required fields:

```json
{
  "type": "io.trisaura.forum.rateContextNote",
  "version": 1,
  "action": "rate_context_note",
  "intent_id": "uuid",
  "author_did": "did:elix:...",
  "target_forum_host": "https://relay.elix.cool",
  "created_at": "RFC3339",
  "expires_at": "RFC3339",
  "note_id": "context-note entity id",
  "level": "helpful|somewhat_helpful|not_helpful",
  "tags": ["fixed_reason_code"],
  "signature": "..."
}
```

One active rating is stored per `(note_id, host_scoped_rater_key)`. A new valid
intent replaces the prior rating and keeps the latest signed intent for audit.

Helpful tags:

- `addresses_claim`
- `important_context`
- `good_sources`
- `clear`

Not-helpful tags:

- `incorrect`
- `sources_missing_or_unreliable`
- `off_topic`
- `opinion_or_speculation`
- `argumentative_or_harassing`
- `outdated`

`somewhat_helpful` may use tags from either family. At least one tag is
required. Unknown tags fail closed.

### Relay / Forum Host tables

`forum_host_context_note_ratings`:

- `note_id`
- `target_ref`
- `board_id`
- `rater_did` (private)
- `rater_key` (HMAC-SHA256 over canonical DID, host-scoped secret)
- `rater_tier`
- `level`
- `tags`
- `intent_id`
- `signed_intent`
- timestamps
- unique `(note_id, rater_key)` and unique `intent_id`

### AppView tables

`context_notes`:

- signed-op provenance (`log_id`, `op_id`, signature, public key, verified_at)
- author and canonical author DID
- target type/id/op id/content hash and optional board id
- body, sources, created time, deleted flag

AppView does not store individual rating records. Statuses are returned by the
Forum Host and merged by clients. This preserves independent verification of
public note authorship without leaking private rating history to a global read
model.

## Scoring V1

Scorer id: `elix_host_consensus`; version: `1`.

Map ratings to values:

- helpful = `1.0`
- somewhat helpful = `0.5`
- not helpful = `0.0`

Quorum is satisfied when either:

- at least 5 distinct active raters including at least 2 `verified_human`
  raters; or
- at least 10 distinct active raters of any anchored-DID tier.

All ratings have equal weight once quorum is met. Trust tier changes the cost
of reaching quorum and rate limits, never the truth value of a person's vote.

Statuses:

- `target_changed`: the target's current active op differs from `targetOpId`.
- `withdrawn`: the context note has an author-signed delete op.
- `needs_more_ratings`: quorum is not met.
- `helpful`: mean score >= 0.80, no critical `incorrect` or
  `sources_missing_or_unreliable` tag reaches 30%, and at least one helpful tag
  is selected by two distinct raters.
- `not_helpful`: mean score <= 0.30 and at least one not-helpful tag is selected
  by two distinct raters.
- `disputed`: quorum is met but neither terminal threshold is met.

Every result includes:

- `status`
- `score`
- `rating_count`
- level counts
- verified-human count
- top tags that have at least two raters
- `reason_codes`
- `scorer_id` and `scorer_version`
- `evaluated_at`
- SHA-256 `input_hash` over sorted opaque rating inputs

V1 must not describe `helpful` as cross-perspective consensus. A later scorer
may use a rating-history-only matrix factorization / Gaussian aggregation after
there is enough overlapping data. That change requires a new scorer version,
calibration tests, published thresholds, and a new constitution review.

## API

Relay / Forum Host:

- `POST /api/v1/ops` accepts validated `context_note` ops.
- `POST /api/v1/forum-host/community-notes/:note_id/ratings` accepts a signed
  rating intent and returns an opaque receipt plus the caller's current rating.
- `GET /api/v1/forum-host/community-notes/:note_id/status` returns one aggregate
  result.
- `GET /api/v1/forum-host/community-notes/statuses?target_ref=...` returns all
  note statuses for a target without individual ratings or rater DIDs.

AppView:

- `GET /api/v1/context-notes?target_ref=...` returns independently verified
  active context notes for one target.

## Moderation

- Extend report targets with `context_note`.
- Host moderators may hide a context note from that host with a fixed reason
  code and an audit record.
- The original signed op remains in Relay and may be displayed by another
  compliant AppView/Host.
- Moderating a context note never changes the target post's visibility.
- Note authors may withdraw with an author-signed delete op.

## Flutter UX

Reusable components:

- `CommunityNotesPanel`: loads independently verified notes plus Host status,
  highlights the highest-scoring helpful note, and exposes other proposals.
- `CommunityNoteComposerSheet`: body, sources, target-revision disclosure,
  preview, and explicit public-publish confirmation.
- `CommunityNoteRatingSheet`: three rating levels, reason tags, and disclosure
  that the Host receives the signed rating while only aggregates are public.

Integrations:

- standalone content detail;
- hosted thread/post detail;
- overflow action: `新增社群脈絡`;
- Settings preference to show/hide Community Notes (default on, local only).

Rendering rules:

- place the highlighted card after target content and before reactions/comments;
- say `社群評價為有幫助`, never `這是錯誤資訊`;
- show sources, host/scorer, top reasons, and rating count;
- `target_changed` displays a revision warning and is never highlighted;
- Host/API failure hides the highlight but never blocks target content.

## Web UX

- Render the same Community Notes card on public native content pages.
- Add note/rating API helpers to the existing session rail.
- Show status/scorer/reasons and never expose rater identities.
- Extend moderator report/action rendering for `context_note` targets.

## Implementation Tasks

### 1. Relay protocol and validation

- [x] Add `context_note` to accepted op types and author-mutation checks.
- [x] Validate payload limits, public visibility, sources, target identity, and
      exact target revision.
- [x] Exclude context notes from ordinary feed distribution and reactions.
- [x] Add focused controller/store tests for valid insert/update/delete,
      malformed payload, bad source, private target, missing target, wrong
      revision, non-author mutation, signature failure, and rate limiting.

### 2. Forum Host private ratings and scoring

- [x] Add rating migration/schema/store.
- [x] Add signed-intent verification and replay-safe upsert.
- [x] Add host-scoped HMAC rater keys and never serialize rater DID publicly.
- [x] Implement scoring V1, target-revision invalidation, aggregate endpoints,
      tier-aware rate limits, and reason-coded metrics.
- [x] Extend reporting/moderation target kinds for context notes.
- [x] Test privacy, signature tampering, replay, replacement, self-rating,
      quorum variants, all statuses, critical-tag guard, stable input hash,
      target change, withdrawal, rate limiting, and moderator scope.

### 3. AppView projection

- [x] Add context-note migration/schema.
- [x] Fold only independently verified public context-note ops.
- [x] Apply update/delete by author and revision order.
- [x] Add target-ref index and read endpoint.
- [x] Test valid projection, invalid signature rejection, private visibility
      rejection, update/delete, pagination/order, and no ordinary feed leakage.

### 4. Flutter

- [x] Add op builder and tests.
- [x] Add AppView/Forum Host models and clients with privacy-safe parsing.
- [x] Add composer, rating sheet, panel, settings toggle, and integrations.
- [x] Test validation, signing/enqueue, API errors, privacy disclosure,
      highlighted/non-highlighted states, target change, withdrawal, setting,
      and failure-tolerant rendering.

### 5. Distribution frontend

- [x] Add public status/note fetch helpers and renderer.
- [x] Add a signed-rating transport that accepts only a caller-produced DID
      intent. Because a web session is not DID custody, the current Web UI uses
      an explicit Elix-app handoff instead of silently substituting session auth.
- [x] Extend moderator target rendering.
- [x] Test escaping, source-link safety, status copy, no rater identity leakage,
      disabled/error states, and moderator actions.

### 6. Cross-layer verification

- [x] Relay focused suite green.
- [x] AppView focused suite green.
- [x] Core/store and Flutter focused suites green.
- [x] Frontend focused suite green.
- [x] Broader regression suites run where local toolchains are available.
- [x] Mark this plan implemented with exact test results and any remaining
      environment-only verification boundary.

## Implementation Result (2026-08-30)

Status: implementation complete and ready for the production delivery pipeline.

- Relay: full `mix test` passes; the Community Notes-focused suite passes 33
  tests, including protocol validation, private-rating privacy, scoring,
  moderation, replay, and rate-limit coverage.
- AppView: full `mix test` passes; the focused projection suite passes 6 tests,
  and the selected ingestion regression suite passes 22 tests.
- Core and Flutter: the relevant suites pass 33 tests, release-readiness and
  passkey regressions pass 18 tests, and `flutter analyze --no-fatal-infos`
  reports no issues. The repository-wide Flutter suite still has 15 unrelated
  pre-existing failures in older notification/home-shell timing and shared-state
  tests; no Community Notes test fails.
- Distribution frontend: the complete `npm test` suite passes.
- Deployment configuration injects a separate production/dev Forum Host rater
  HMAC secret into both Relay migrations and runtime without publishing it.

The remaining boundary at commit time is environment-only: the `prod` Cloud
Build pipelines must run their Relay/AppView migrations before traffic, the
anonymous production read endpoints must be probed after deployment, and a new
iOS archive must be built with `config/production.json` and uploaded to App
Store Connect. These operations do not change the protocol or implementation
defined by this plan and are reported separately from TestFlight processing and
availability.

## Definition Of Done

A user can attach a signed, sourced Community Note to an exact public Elix
content revision; AppView independently verifies and serves it; another user
can privately submit or replace a signed usefulness rating; the Forum Host
publishes a transparent aggregate decision without exposing any rater DID; app
and web show the host-scoped result without altering the target's distribution;
target edits invalidate the highlight; authors can withdraw notes; abusive notes
remain reportable and host-scoped moderation is audited; and each behavior has
automated positive, negative, privacy, and abuse-path tests.
