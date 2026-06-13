# Elix (Ansible) UX/UI Review — 2026-06-13

> Scope: the Flutter app at `ansible_node/app` (`lib/screens/`, `lib/screens/home/`,
> `lib/widgets/`, `lib/l10n/`, `lib/theme/`) and the public web frontend at
> `ansible_distribution_frontend/src`. Read against `README.md` and
> `docs/ROADMAP.md`. This is a design review of real flows read from the code,
> not a spec audit. No code was changed.

---

## Executive summary

Elix has an unusually mature and *opinionated* design system for a pre-launch
local-first app: a cohesive "Forest Letter" palette with paired light/dark
themes (`theme/ansible_design.dart`), a custom mark/wordmark, a tasteful
serif+mono type pairing, a per-board theming model, and a genuinely novel
three-board swipe interaction with book/curl/slide physics that respects
`disableAnimations`/`accessibleNavigation`. The newly shipped P1 features
(trust-gated boards, reporting/moderation, notifications) are not bolted on —
their *states* (loading/empty/error/blocked, tombstones, locked banners,
author-visible removal notices) are handled with real care and tie back to the
constitution. The single biggest opportunity is **onboarding and the
create-content loop**: the first screen still sells an engineer's mechanism
("先建立身分 / Create identity first") rather than a user outcome, the
post-registration first session has no guided next step, and the core compose
dialogs (`PostFormDialog`, `BoardFormDialog`) are hardcoded English in an
otherwise fastidiously bilingual app — so the very first thing a zh-Hant user
does (write a post) breaks the language contract. Fixing the funnel from
"installed" → "first post / first follow" is higher leverage than any new
feature.

---

## Top findings

| # | Finding | Severity | Affected screen(s) | Recommendation |
|---|---------|----------|--------------------|----------------|
| 1 | Core compose/edit dialogs are hardcoded English ("New Post", "Content", "Cancel", "Post", "Save", "Title", "Create hosted board") in a fully bilingual app | **P1** | `lib/widgets/post_form_dialog.dart` (entirely), `lib/widgets/board_form_dialog.dart:58-167` (title/labels/buttons), `lib/screens/posts_view_screen.dart:252-267` (delete dialog), `:328-336` (empty state), `:393-398` ("(edited)") | Route every string through `context.uiCopy(zh:, en:)`. This is the primary create loop for the primary (zh-Hant) audience. |
| 2 | Onboarding value prop is mechanism, not benefit | **P1** | `passkeys_registration_screen.dart:366-374` ("先建立身分，再開始社群" / "Create identity first, then join the community") | Lead with the outcome the roadmap itself names: 「沒有機器人的討論區」「帳號和內容永遠是你的」. Demote the DID/passkey machinery to the existing promise rows. |
| 3 | No guided post-registration first session | **P1** | `home_shell.dart:302` (`_showFirstRunDiscovery`), `home/first_run_discovery.dart`, `home/timeline_board.dart:70-125` | First-run discovery only shows when there's no relay/host; once auto-seed runs it can vanish. Add an explicit "first 3 things" empty state on the Personal board: subscribe a genesis board, follow suggestions, write your first murmur. (ROADMAP "Improve" item.) |
| 4 | "Verified only / 真人版" gate is discoverable but the *upgrade path is a dead end at MVP* | **P1** | `widgets/posting_gate_notice.dart:76-90` → `AddCredentialScreen`; `widgets/board_gate_badge.dart` | The CTA "升級驗證" leads into the credential wizard, but TW-provider production is fail-closed (README/ROADMAP). A user who taps it will hit a wall. Set expectations in the notice ("目前開放 …") or gate the CTA on a configured issuer, so the flagship feature doesn't produce a confusing dead end on day one. |
| 5 | Discover is buried; the local-first "ghost town" risk has no in-feed escape hatch | **P1** | `discover_screen.dart` reachable only from `home/timeline_board.dart:104` (empty-timeline button) and `home/top_bar.dart:134` (desktop) | On compact/mobile there is no persistent entry to Discover from Personal/Forum boards — only from the empty Timeline. Add a Discover affordance to the board header icon cluster (next to the bell) so finding people/boards is always one tap away. |
| 6 | Delete confirmation is unstyled + English; destructive action under-protected | **P2** | `posts_view_screen.dart:250-268` | Localize; match the themed `AlertDialog` pattern used elsewhere (e.g. `home_shell.dart` board delete uses `l10n.deleteBoardConfirm`). |
| 7 | Notifications screen has no link to its own settings | **P2** | `notifications_screen.dart:251-303` (AppBar trailing only has "Mark all read") | Add a gear/▦ action routing to `NotificationSettingsScreen`; today settings are only reachable via Settings → Notifications, two levels away from where intent forms. |
| 8 | Three-board swipe model + tab semantics are subtle and under-explained | **P2** | `home/board_swipe_header.dart`, `home/swipe_coachmark.dart`, `home_shell.dart:520-561` | The coachmark fires once; the Personal/Timeline/Forum distinction (and that Timeline==follows, Forum==boards) is conceptually heavy. Consider a persistent thin progress pill (already built in `board_swipe.dart:113`) plus clearer first-use labeling. |
| 9 | Reading-preferences text scale not obviously honored app-wide; `appTextScale=1.08` is a const | **P2** | `theme/ansible_design.dart:48`, `reading_preferences_screen.dart`, many `const TextStyle(fontSize:)` | Heavy use of hardcoded `fontSize` with `const TextStyle` means user text-scale and OS Dynamic Type may not propagate to a lot of chrome. Verify large/extra-large actually reflow; audit mono labels at 8.5–10px against scaling. |
| 10 | Tiny mono labels at 8.5–9px risk contrast/legibility, esp. CJK fallback | **P2** | `ansible_design.dart` (`navTextSize`/meta labels), `passkeys_registration_screen.dart:336-354` (10px), settings `'SIGNED · PASSKEY'` 8.5px | `inkFaint (#88826E)` on `paper (#FBF7DC)` at 8.5–9px is borderline WCAG AA. Set a floor (≥11px) for any text a user must read, reserve <10px for pure decoration. |

---

## Per-area detail

### 1. First-run / onboarding (`passkeys_registration_screen.dart`)

**What's good:** A real 1/3 progress framing, a 3-step live phase indicator
(`_buildPhaseIndicator`, lines 531-599) with spinner→check states, two
"promise" rows that *do* speak benefit ("身分在你這裡 / Identity stays with you",
lines 401-422), inline handle field with `.elix.cool` suffix, and a thorough,
fully-localized error taxonomy (`_formatError`, lines 230-312) covering
duplicate handle, expired nonce, signature mismatch, rate limiting, passkey
device auth, etc. This is well above typical MVP onboarding.

**Problems:**

- **Headline sells the mechanism.** `:366` "先建立身分，再開始社群" is exactly the
  "engineer-speak" the ROADMAP "Improve" row flags. The benefit copy is buried
  in the italic sub-paragraph (`:378-381`). Swap: lead with "沒有機器人的討論區 ·
  你的帳號永遠是你的", make identity the *how*.
- **"SOCIAL FIRST" mono kicker** (`:346`) is English-only and cryptic to a
  zh-Hant reader; either localize or drop.
- **No empty state after success.** `onRegistered` hands off to `HomeShell`,
  which lands on the Personal board. There is no "welcome, here's what to do
  next" — see finding #3.
- The screen header still carries Secure Enclave / StrongBox language in its
  doc comment (`:13-19`) and `_signNonce` doc (`:182-189`) — harmless to users,
  but note the constitution compliance work (ROADMAP gap #1) is explicitly
  *deferring* hardware custody; keep UI copy from re-introducing the overclaim
  (the registration UI itself correctly says only "由 passkey 支撐").

### 2. Core loops

**Home shell / boards (`home_shell.dart`, `home/`):** The swipe pager across
Personal → Timeline → Forum is a strong, differentiated idea, and the header
(`board_swipe_header.dart`) interpolates colors smoothly across boards. The
book/curl motion (`board_swipe.dart:15-111`) correctly degrades under reduced
motion. But the conceptual load is high: a new user must learn that Timeline =
people you follow, Forum = boards, Personal = your own murmurs/notes, *and* that
swiping changes which compose actions apply. The single-shot coachmark
(`_checkCoachmark`, `:563`) is the only teaching moment.

**Compose (`_openCompose`, `home_shell.dart:619-673`):** Clean bottom sheet with
Murmur/Note. But the actual editors behind it — `PostFormDialog` — are the
hardcoded-English finding #1. The compose sheet only offers Murmur/Note;
creating a *thread* (`_createThread`) and *board* (`_createBoard`) is reached
elsewhere, and board creation surfaces raw `Could not create board: $e`
(`:1076`) — acceptable as a fallback but it leaks exception text into a
user-facing snackbar.

**Reading a thread (`posts_view_screen.dart`):** Functionally complete and the
moderation states are excellent (see §3), but this screen is the worst offender
for English leakage: empty state "No posts yet / Be the first to post"
(`:328-336`), `(edited)` (`:397`), the whole Delete dialog (`:252-267`), and the
PopupMenu "Edit"/"Delete" labels (`:409-431`) are hardcoded. The avatar is the
first letter of a raw DID (`:374-377`) — for `did:plc:...` that's always "D",
which is meaningless; prefer the contact label/handle when resolvable.

**Discovery (`discover_screen.dart`):** Genuinely good — debounced search
(`:94`), separate feed vs. search section sets, per-section empty states, a
proper retry error pane (`_errorPane`, `:349`), verified badge on actors
(`:429`), and the `BoardGateBadge` on gated boards (`:490-494`). The weakness is
*reachability* (finding #5): on mobile it's only behind the empty-Timeline CTA.

### 3. Newer features (trust-gated boards, reporting/moderation, notifications)

This is the strongest part of the codebase from a "did they handle the states"
standpoint.

**Trust-gated boards:** `BoardGateBadge` ("真人版 / Verified only") shows on
board rows *before* opening the composer (discoverability requirement met).
`PostingGateNotice` replaces the composer with an explanation + "升級驗證" CTA
and re-checks on return (`onUpgradeCompleted` → `_loadPosts`,
`posts_view_screen.dart:495-498`). The relay-rejection path is also localized
(`user_facing_error.dart:39-45`). **Gap:** the upgrade CTA can be a dead end at
MVP (finding #4), and the gate notice doesn't tell the user *which* verification
unlocks it.

**Reporting + moderation:** `report_dialog.dart` is a clean reason-coded picker
with a required-note rule for "other" (`:52-62`), correctly explains that
reports are signed and handled by moderators. Reporting is correctly hidden for
your own content and for non-hosted boards (`:299-300`, `:436-437`). The
moderation *outcome* rendering in `posts_view_screen.dart` is exemplary and
constitution-aligned: locked-thread banner + composer replacement
(`:518-591`), reason-coded tombstones for others' removed posts (`:595-631`),
and an author-visible removal notice that keeps the local copy
(`:636-658`). Notifications even synthesize a "板務 / Board moderators" actor
for moderation events (`notifications_screen.dart:174-178`). Very well done.

**Notifications:** In-app feed (`notifications_screen.dart`), unread bell with
local-only badge truth (`board_swipe_header.dart:460-519`, count from the device
table — `home_shell.dart:1219-1225`), per-category toggles + a content-free push
opt-in that *explains the privacy model in plain language* and handles the
"FCM/APNS not configured" case gracefully instead of silently failing
(`notification_settings_screen.dart:97-110`, `:227-234`). Empty state is warm
and on-brand (`:397-444`). **Gaps:** no in-screen jump to notification settings
(finding #7); the moderation-outcome row does a second DB lookup to recover the
reason code (`:73-85`) which is fine but fragile if the overlay hasn't synced —
the fallback copy is correct though.

### 4. Information architecture & navigation

- **Swipe + tab coherence:** The model is novel but heavy (finding #8). The
  desktop layout adds a 280px sidebar (`home_shell.dart:1597-1609`) which is a
  good adaptive choice.
- **Settings (`settings_home_screen.dart`):** Well-organized into Identity &
  Device / Interface & Language / Daily / Boundaries / About, with a clean
  identity header carrying the `ElixSignedPill`. Good localization via
  `_SettingsText` with zh fallbacks. Minor: the "備份與還原 / RECOVERY" row shows
  "未設 (not set)" in ember and has no `onTap` (`:271-278`) — it's a visible
  promise of an unbuilt feature (recovery is a launch blocker per ROADMAP); make
  sure it doesn't read as broken. "收信 / INBOX" hardcodes value `'0'`
  (`:240`) and Inbox vs. Notifications is a confusing overlap.
- **Version string** is stale/inconsistent: `'ANSIBLE · v0.7.2 · LOCAL-FIRST'`
  (`:306`) still says "ANSIBLE" while the whole product is now "Elix".
- **Wallet/credential flows** are deep (`wallet_screen`, `add_credential_screen`,
  `credential_issuance_wizard`, multiple provider screens). Not fully audited
  here, but the entry from `PostingGateNotice` ties the gate to the wallet,
  which is the right mental model — provided the issuer is actually available.

### 5. Visual / interaction consistency

- **Theme usage is strong and consistent** (`ansible_design.dart`): one source
  of truth for color, paired light (Bone Goose) / dark (Pine), component library
  (`ElixSignedPill`, `AudienceChip`, `ElixSourceLabel`, `DiaryEntryCard`,
  `ElixAgentSheet`). The per-board `ElixScreenStyle` system is a differentiator.
- **Bilingual copy is ~95% consistent via `uiCopy`** — which makes the English
  islands (finding #1, #6) stand out as *bugs*, not stylistic choices. The web
  frontend has a proper key-based i18n (`web_i18n.mjs`, zh-Hant default + en)
  with full coverage including moderation/report/trust strings — the web side is
  actually *more* disciplined than the app here.
- **Error message quality is high** (`user_facing_error.dart`): protocol-version
  upgrade, rate-limit, thread-locked, posting-requires-tier, socket/timeout/
  format all mapped to short localized copy with a safe generic fallback that
  trims raw exception text. The web mirror (`forum_ui_text.mjs:describeError`)
  is equally thorough. Exception: a few ad-hoc snackbars still interpolate `$e`
  (`home_shell.dart:1076`).
- **ROADMAP decision to cut de/es/fr/ja/ko/pt** is well-founded — those ARB
  files exist (`lib/l10n/app_*.arb`) but most screens bypass ARB via `uiCopy`,
  so they're a maintenance liability with no payoff.

### 6. Accessibility & polish

- **Good:** Reduced-motion respected in the board pager
  (`board_swipe.dart:38-47`); board tabs have `Semantics(button, selected,
  label)` (`board_swipe_header.dart:253-256`); icon buttons use 44–48px tap
  targets explicitly (`:128-145`, `:482`); tooltips on board tabs and icons.
- **Concerns:**
  - Tiny type (finding #10): multiple 8.5–10px mono labels in faint ink; below
    comfortable contrast/size, and JetBrains Mono lacks CJK glyphs (the code
    even comments on this in `board_swipe_header.dart:321-323`) so any CJK that
    lands in a mono style renders an odd fallback.
  - Text scaling (finding #9): pervasive `const TextStyle(fontSize:)` plus a
    constant `appTextScale` suggests chrome may not respond to the
    reading-preference scale or OS Dynamic Type; needs a real large-text pass.
  - Report dialog `RadioListTile`s are `dense` with zero content padding
    (`report_dialog.dart:98-99`) — verify the tap target stays ≥44px.
  - Avatar from DID first char (`posts_view_screen.dart:374`) is not meaningful
    and not accessible; use resolved handle/label.

---

## Quick wins (high impact, low effort)

1. **Localize the compose/edit/delete dialogs** (`post_form_dialog.dart`,
   `board_form_dialog.dart`, `posts_view_screen.dart` delete dialog + empty
   state + "(edited)" + popup menu). Pure `uiCopy` wrapping; closes the most
   jarring consistency bug in the primary loop. (Findings #1, #6)
2. **Rewrite the onboarding headline** to a benefit (`:366-374`) and
   localize/drop "SOCIAL FIRST". (Finding #2)
3. **Add a Discover icon** to the board header cluster next to the bell so it's
   always reachable on mobile. (Finding #5)
4. **Add a settings (gear) action to the Notifications AppBar.** (Finding #7)
5. **Fix the stale brand/version string** `'ANSIBLE · v0.7.2'` → Elix. (IA)
6. **Stop leaking `$e` in the create-board snackbar** — route through
   `userFacingError`. (`home_shell.dart:1076`)
7. **Set a minimum readable font size (≥11px)** for any non-decorative label and
   bump the 8.5–9px meta labels. (Finding #10)

## Bigger bets

1. **Design the first-run "first three actions" experience** end-to-end:
   subscribe a genesis board → follow 2–3 suggested people → write your first
   murmur, with progress that persists across the session. This is the client
   half of the cold-start item and the highest-leverage retention work.
   (Finding #3)
2. **Make the trust-gate upgrade path honest and complete.** Either gate the
   "升級驗證" CTA on a configured issuer, or design an interim state ("真人驗證
   即將開放") so the flagship differentiator never dead-ends. Then design the full
   verify → tier-up → "you can now post here" loop. (Finding #4)
3. **Teach the three-board model.** A short, skippable first-use tour (or a
   persistent, quieter wayfinding cue) for Personal/Timeline/Forum + what each
   compose action does. (Finding #8)
4. **A real accessibility + text-scaling pass** that makes reading-preference
   scale and OS Dynamic Type propagate through chrome, with large-text reflow
   QA. (Findings #9, #10)
5. **Sharing / deep links** (ROADMAP P2): OG tags on the frontend + share sheet
   in app. The natural forum growth channel (content → LINE/Threads → visit →
   register) is currently closed; this is a UX surface, not just backend.

---

## Non-goals / things that are already good (don't regress these)

- **The design system** (`theme/ansible_design.dart`) — palette, dark theme,
  component library, type pairing. Cohesive and distinctive; keep new UI inside
  it rather than inventing one-off styles.
- **Per-board theming + board-swipe motion** (`ElixScreenStyle`, `board_swipe`).
  A real differentiator; preserve the reduced-motion handling.
- **Moderation-state rendering** in `posts_view_screen.dart` (tombstones, locked
  banners, author-visible removal-with-local-copy). Constitution-aligned and
  carefully built — a model for how other states should be handled.
- **The localized error taxonomy** (`user_facing_error.dart` and the web mirror
  `forum_ui_text.mjs`). Keep all new error surfaces flowing through these.
- **Privacy-forward copy** in notification settings and the AI agent sheet
  ("僅處理本機內容，不離開裝置", content-free push explanation). On-brand and
  trust-building; reuse this voice.
- **The web frontend's key-based i18n** (`web_i18n.mjs`) with zh-Hant default —
  it's the discipline the app's compose dialogs should match.
- **Local-only badge truth** for the notification bell — correct privacy
  architecture *and* correct UX; don't let a future push feature move the count
  to the server.
