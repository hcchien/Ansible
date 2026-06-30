# Handoff · Elix Social App

A privacy-first, identity-sovereign social network. Feed-first product surface, identity infrastructure underneath. The name "Elix" derives from *Elixir* (萬靈丹).

---

## About the design files

The HTML files in this bundle are **design references** — high-fidelity prototypes built to communicate intended visuals, layout, copy, and behavior. They are **not production code to copy directly**.

Your task is to recreate these designs inside the target codebase's existing environment — pick the framework, component library, and styling approach that fits the codebase. If no codebase exists yet, choose the most appropriate stack (React + Vite + Tailwind, Next.js, SwiftUI for iOS, etc.) and build there. Treat the HTML as a spec.

The product has three surfaces, all in this bundle:

| File | What it is | Status |
|---|---|---|
| `Elix Web.html` | Web app — Desktop / Tablet / Mobile breakpoints, 6 key views | Built using the **previous palette (Amber / Sage)** |
| `Elix Screens.html` | iOS app — 20 screens across onboarding / feed / posts / social / settings | Built using the **previous palette (Amber / Sage)** |
| `Elix Forest Letter.html` | **The current chosen palette** — apply this on top of everything else | **Use these tokens for implementation** |
| `Elix Brand System.html` | Earlier brand-system reference (logo, app icons, color system, theme) | Background reference; latest palette overrides this |

**Important:** `Elix Web.html` and `Elix Screens.html` were built with the earlier *Amber + Sage* palette. The selected direction is now **Forest Letter** (`Elix Forest Letter.html`). When implementing, **apply the Forest Letter tokens below to everything** — the structure / layout / typography in the older files is still correct, only the color tokens change.

## Fidelity

**High-fidelity.** Final colors, typography, spacing, copy, interactions, and component states. Recreate pixel-perfectly using the codebase's design system / component library.

---

## Brand identity

### The mark
A constellation (three nodes connected by lines, rotated 30°) with a smaller dot at its center — the "trust dot." See `Elix Forest Letter.html` for the SVG.

```svg
<svg viewBox="-100 -100 200 200">
  <g transform="rotate(30)">
    <g stroke="currentColor" stroke-width="9" stroke-linecap="round" fill="none">
      <line x1="-60" y1="40" x2="60" y2="40"/>
      <line x1="-60" y1="40" x2="0" y2="-60"/>
      <line x1="60" y1="40" x2="0" y2="-60"/>
    </g>
    <g fill="currentColor">
      <circle cx="-60" cy="40" r="14"/>
      <circle cx="60" cy="40" r="14"/>
      <circle cx="0" cy="-60" r="14"/>
    </g>
    <circle cx="0" cy="6" r="8" fill="var(--ochre)"/>
  </g>
</svg>
```

`currentColor` lets the mark inherit the surrounding text color; the inner trust dot is always the ochre accent.

### Wordmark "Elix"
A custom geometric all-caps wordmark, drawn from scratch as SVG paths (see `Elix Brand System.html`). Signature move: the **X is split into four diagonal strokes with a small diamond gap at the centre**, and the **I has an amber tittle** (dot above) that echoes the trust dot. **Do not substitute with any system / web font** — the wordmark IS the SVG. Render as SVG.

---

## Design tokens — Forest Letter (use these)

### Colors

| Token | Hex | Role |
|---|---|---|
| `--bg` | `#FBF7DC` | Primary surface (Bone Goose) |
| `--bg-soft` | `#F4EEC6` | Soft surface (Vellum) |
| `--bg-deep` | `#E8DEAA` | Deeper surface, anonymous post background |
| `--fg` | `#1F2E20` | Text and marks (Forest ink) |
| `--fg-muted` | `#3D4E3D` | Secondary text |
| `--fg-faint` | `#88826E` | Tertiary / metadata text |
| `--rule` | `#D6CB94` | Borders |
| `--rule-soft` | `#E3DAB0` | Subtle dividers |
| `--ochre` | `#B88C2E` | Accent · the trust dot, signed indicators, primary signal |
| `--moss` | `#5A6E3A` | Secondary · circle / signed-by-others |
| `--ember` | `#7E4A1E` | Warning / destructive |

### Dark theme (Pine)

| Token | Hex |
|---|---|
| `--bg` | `#0E1A0F` |
| `--bg-soft` | `#16221A` |
| `--bg-deep` | `#1F2D24` |
| `--fg` | `#E8E0BE` |
| `--fg-muted` | `#B8B49A` |
| `--fg-faint` | `#7C8071` |
| `--rule` | `#2A3526` |
| `--rule-soft` | `#1F291E` |
| `--ochre` | `#D9AB4E` |
| `--moss` | `#93A971` |

Support `prefers-color-scheme` and a manual toggle (persist in `localStorage`).

### Typography

| Use | Family | Notes |
|---|---|---|
| Serif (body, headings, post text) | `'Noto Serif TC', 'Newsreader', serif` | The primary voice — editorial, considered |
| Serif EN (English body) | `'Newsreader', 'Noto Serif TC', serif` | Use for italics and English-heavy text |
| Sans (UI chrome) | `'Noto Sans TC', system-ui, sans-serif` | Only for system chrome |
| Mono (metadata, labels, fingerprints, timestamps) | `'JetBrains Mono', 'IBM Plex Mono', monospace` | All caps + 0.14–0.18em letter-spacing for labels |

### Type scale (web)

- Display heading: `clamp(28px, 3.5vw, 44px)` weight 500
- Page H1: 28px weight 500
- Section H2: 22px weight 500
- Body: 16px / 1.7 line-height (serif)
- Post body: 16px / 1.7
- Small body: 13.5px / 1.65
- Meta (mono uppercase): 10px / `0.14–0.18em` letter-spacing
- Tiny meta: 9–9.5px / 0.1–0.18em letter-spacing

### Type scale (iOS app)

- Display: 28px / 1.2
- H2: 22px / 1.3
- Note title: 17px / 1.35 weight 500
- Body: 14–14.5px / 1.65 serif
- Mono labels: 8.5–10px / 0.14–0.18em letter-spacing

### Spacing & radius

- Card padding: 18–24px
- Section gap: 14–22px
- Border radius: cards = 10–14px, pills = 999px, app icon tile = 32px
- Hairline borders: `0.5px solid var(--rule)` — use 0.5px not 1px, the system depends on hairlines feeling like ink lines, not UI strokes

### Shadows
Very restrained. Cards have **no shadow** by default — they're defined by hairline borders. Reserve shadow for:
- Modal sheets / popovers: `0 24px 60px rgba(31,46,32,0.18)`
- App icon tiles: `0 14px 32px rgba(31,46,32,0.18), 0 2px 6px rgba(31,46,32,0.08)`

---

## Core product concepts (read before implementing)

### Two post types: Note and Murmur
- **Note** — text post, can have title. Long-form, considered. Marked with a black (Forest ink) pip.
- **Murmur** — voice post, max 2 min, auto-transcribed. Marked with an ember pip. Posts include an inline audio player with waveform + the transcript shown as italic blockquote with `"` prefix.

Both types appear in feeds. The post-source row above every post tells the user **why it appears** (e.g. "FROM A FOLLOW — 你在三月關注了 Mira" or "BOARD · #PHILOSOPHY — 你訂閱了這個板"). This transparency is part of the brand promise — never hide ranking logic.

### Trust signal: the amber "✓PK" pill
Signed posts show a small pill next to the author name (`✓PK` / `SIGNED · PASSKEY`). Different trust tiers:
- **PASSKEY** — ochre, primary
- **DID / SELF-CUSTODY** — ochre with longer label
- **WEB · PASSKEY** — moss (web session, derived)
- **BASIC** — fg-faint (anonymous / unsigned)

The trust signal is a **pill with border**, never a free-floating dot — a dot is too easily misread as "online status."

### Audience model
Every post has an explicit audience set on compose:
- Followers (your followers)
- A specific board (#philosophy, #tools, etc.)
- Circle (your trusted inner circle — passkey-paired, no central server)

Mix and match. The composer surfaces audience as colored chips (ochre for follower, moss for board, etc.).

### Anonymous posts
Allowed in some boards. Background is `--bg-soft` (subtly different from regular posts), author name is italic muted color, no signature pill. Anonymous identity persists per-board so a thread of replies is consistent, but cannot be linked across boards.

### Circles
Local groups, 8 members max, P2P passkey-paired. No central server, no admin. Posts to circle don't appear in public feeds.

### Identity = wallet of keys
Users have a primary DID (`did:elix:...`) and can have multiple alter identities (anonymous-for-board, work-DID, etc.). Backed by passkeys. **No password reset** — emphasised in onboarding. Encrypted backup with passphrase is offered but optional.

### "Why this post" / source labels
Every post / discovery card has a `mono` label above it in caps explaining the relationship: `FROM A FOLLOW`, `BOARD · #PHILOSOPHY · 匿名`, `MURMUR · 0:42 · BY YOU`. Implement this as a required component prop, not an optional one.

---

## Web screens (`Elix Web.html`)

7 views, all desktop @ 1280 unless noted. Apply Forest Letter palette.

### 01 · Home (Feed)
Three-column layout:
- **Left rail (280px)**: Navigation (動態 / 發現 / 通知 / 圈內 / 論壇板) + Following (8 people) + Subscribed boards (4)
- **Center (1fr)**: Composer card → 4 feed tabs (動態 · 追蹤的人 · 訂閱的板 · 圈內) → mixed feed
- **Right rail (320px)**: Circle activity / suggested boards / people to follow / italic kicker line "動態是按時間排序的，沒有演算法決定你看見什麼"

Feed shows Notes, Murmurs, board posts, anonymous posts. Each card: source row → author row → body → image (optional) → action row (共鳴 / 回覆 + signed pill).

Three action buttons total: **共鳴 (resonate)**, **回覆 (reply)**, and the signed pill. No "pass on to circle" — that was removed.

### 02 · Profile (other user)
Same three-col layout. Center column starts with:
- Profile head: large avatar + name + signed pill + handle + bio + 3 action buttons (已追蹤 / 加入圈內 / 私訊) + stats row (發文 / 共鳴 / 被信任 / signed since)
- Feed tabs (發文 / 媒體 / 共鳴過 / 共同板)
- The user's posts below

Right rail: "關於 MIRA" card (true identity status, trust tier, common boards, common circle members) + 共同追蹤的人 card.

### 03 · Login (App-mediated)
- Heading: "從你的 App 確認登入"
- Two-column grid (1.2fr 1fr):
  - QR block (200×200 stylized QR with corner finders) + deep-link
  - Challenge details card: Challenge ID, Expires, Deep link, requested scopes as chips
- Banner: "瀏覽器只是視窗 — 鑰匙留在 App 裡"

### 04 · Compose
- 3 post-type tabs at top: **Note / Murmur / 到板上發言**
- Large title input (32px serif, no border)
- Body editor (17px serif, line-height 1.8)
- Below: AUDIENCE chip strip (ochre = followers, moss = board)
- Right rail: SIGNATURE card (current signing identity, change-to options), keyboard shortcut hint

### 05 · Thread (post detail)
- Original post in full
- Inline reply composer (cream card with avatar, italic placeholder, "SIGNING AS @TRIS" indicator, anonymous toggle, send button)
- Replies list with hairline dividers, each shows author + signed pill + body + meta line

### 06 · Settings (Identity & Keys)
Left sidebar with 7 sections (身分與鑰匙 · 動態與發文 · 隱私與受眾 · 裝置與 sessions · 通知 · 介面與語言 · 封存或銷毀身分). Currently shown: Identity & Keys.
- PRIMARY identity card (ochre border, did:elix prefix, fingerprint, sync status)
- ALTER IDENTITIES list (anonymous-for-board, work-DID, "+ create new")
- Encrypted backup section (ember warning if not yet backed up)

### 07 · Interface & Language
- Theme: 3 picker cards (Paper / Ink / Auto) with mini previews
- Language: radio list with translation completeness percentage
- Typography: serif/sans/Songti switcher + size slider (14/16/18/20)
- Motion & density: reduce-motion toggle, density radio (寬鬆 / 舒適 / 緊湊), "Show why this post" toggle (on by default)
- Dashed footer card: "在這台裝置上生效 · LOCAL ONLY" — preferences don't sync across devices

### Tablet (768) and Mobile (375)
Same content, collapsed:
- **Tablet**: Right rail collapses, header context stacks
- **Mobile**: Both rails collapse, hamburger menu, bottom tab bar appears (HOME / FIND / BELL / YOU), compose becomes FAB

---

## iOS app screens (`Elix Screens.html`)

20 screens across 5 sections. iOS dimensions 375 × 812, render inside iOS bezel. Apply Forest Letter palette.

### A · Onboarding (4 screens)
- **A·01 Welcome** — Large mark + wordmark + manifesto ("一個你可以重新開始說話的地方") + primary CTA "開始" + ghost CTA "我已經有 Elix 身分"
- **A·02 Promise** — Three bullets explaining "Elix 不會替你保管你的身分": no server password, no "forgot password", no algorithm
- **A·03 First Key** — Animated ochre ring with key icon, generated DID + fingerprint + italic note "如果你想，可以稍後設定加密備份"
- **A·04 Follow Recommendations** — 3 suggested people to follow, framed as "這不是演算法，是這個 relay 上目前活躍且共識度高的成員"

### B · Feed (3 screens)
- **B·04 Home Feed** — Header (mark + Elix wordmark + search + session chip), feed tabs (動態 · 追蹤 · 板 · 圈內), post stream, tab bar (動態 · 圈內 · [+] · 通知 · 你)
- **B·05 Compose action sheet** — Blurred backdrop, sheet with 3 options (寫一篇 Note · 錄一段 Murmur · 到板上發言), each with icon + title + italic description
- **B·06 Post Detail** — Full note with author and signed pill, "7 個回覆 · 全部簽署" header, reply list mixing signed (passkey, DID) and anonymous

### C · Post Types (3 screens)
- **C·07 Note Editor** — Title input + body editor + audience strip (chips for followers + #design) + signature section block with "改為匿名" / "DID" alternatives
- **C·08 Murmur Capture** — Recording state: ochre concentric ring with stop button, live waveform, italic transcript appearing in real-time, max 2:00 indicator
- **C·09 Murmur Published** — Success banner "發布成功 — 你的 Murmur 現在出現在 24 個追蹤你的人的動態裡", inline player, audience preview (avatar stack + count)

### D · Social (4 screens, including Discover)
- **D·10 Profile (other)** — Compact profile head + feed tabs (Notes / Murmurs / 共鳴過) + their posts mixing types
- **D·11 Circle** — Ochre highlight card "圈內 · 4 / 8 上限" with rule explanation, "本週簽署過 · 4" list of inner members
- **D·12 Notifications** — Filter tabs (全部 · 共鳴 · 回覆 · 圈內), TODAY / YESTERDAY sections, mixed signed (avatar with amber bg) and anonymous notifications
- **D·13 Discover** — Search input at top, 5 filter tabs (全部 · 人 · 板 · Notes · Murmurs), "最近查過" recent searches, "本週活躍" recommendations (board / popular note / suggested people)

### E · You (5 screens)
- **E·13 You Hub** — Your profile head + 4 stats (發過 · 追蹤你 · 你追蹤 · 圈內) + tabs (Notes · Murmurs · 草稿 · 已封存) + your posts
- **E·14 Subscribed Boards** — Italic note explaining boards mix into feed + "你訂閱的 · 4" list with posting/read-only permissions + "你可以再訂閱" suggestions
- **E·15 Single Board** — Board header card (POSTING/READ-ONLY indicator) + thread list with note titles + author lines
- **E·16 Wallet (Identity)** — PRIMARY identity card with DID + fingerprint + sync status + alter identities list + authorized devices list (3 devices including this iPhone)
- **E·17 Settings** — Hierarchical settings: 身分 · 動態與發文 · 資料 · 介面 (with 3-card theme picker: Paper / Ink / 系統) · 語言

### E·18 Board Reply Composer
- Quote of original post in cream block at top
- Cursor-blinking body editor
- Tool row (Pen / Mic / Board attachment) + character counter
- Audience strip locked to "此板" + "不發到動態" chip
- Signature block: "PASSKEY · @TRIS" (passkey required by this board, 匿名 button shown but greyed out with "不可用" label)

---

## Components to build (suggested list)

Build a reusable component layer. Suggested primitives:

- `<ElixMark>` — the constellation SVG, accepts size and color (color flows to lines + outer dots; trust dot is always ochre)
- `<ElixWordmark>` — the custom "Elix" SVG
- `<SignedPill kind="PK | DID | WEB" />` — the trust badge with ✓ checkmark
- `<PostCard>` — accepts source/author/body/actions slots
- `<MurmurPlayer transcript audio duration />` — audio player + waveform + italic transcript
- `<AudienceChip color="ochre" | "moss" | "ember">` 
- `<SourceLabel kind="follow" | "board" | "circle" | "murmur" | "note" />` — the "why this post" mono caps row
- `<FeedTabs>` — pill group, active tab uses bg + border
- `<SessionChip>` — avatar + name + tier mono label
- `<SectionBlock>` — generic card with ochre mono uppercase heading

---

## Interactions & states

### Theme toggle
- Top-right floating pill, "PAPER · LIGHT" or "INK · DARK"
- Persisted in `localStorage`, key `elix-theme`
- Adding `.dark` class to body (or document root) flips token values

### Compose flow
1. User taps `[+]` in tab bar → action sheet appears (Note / Murmur / Board)
2. Note: full-screen editor with title + body + audience + signature
3. Murmur: recording screen with live transcript, max 2 min, stop → publish flow
4. After publish: success banner showing recipient count

### Reply
- Inline composer expands in-place on a thread
- Author identity is shown ("SIGNING AS @TRIS") with one-tap anonymous toggle (only if board allows)
- Some boards require passkey signature; anonymous button shows as disabled with "不可用" label

### Resonate (✦ icon)
- Tap toggles state, count updates locally
- Resonating broadcasts to circle (visible in "Circle 動態" rail)

### Follow / Circle add
- "+ 追蹤" → "已追蹤" (solid pill)
- Adding to circle requires the other party to confirm on their device — show pending state until confirmed

### Sign-in (web)
- Web is read-only by default
- Clicking any write action while unauthenticated → redirects to `/login`
- App-mediated challenge: QR shows for 5 min, polls for completion, then redirects back

### Anonymous mode (per board)
- Anonymous identity is stable within a board (`anonymous_x9b3` persists)
- Cannot be cross-referenced between boards
- Posts use `--bg-soft` background to subtly differentiate

### Empty / loading / error states
- Empty feed: italic kicker "你還沒追蹤任何人 — 從發現開始" + link to Discover
- Loading: hairline-only skeleton boxes, no spinners
- Error: ember-bordered banner with brief explanation, never modal

---

## Responsive breakpoints

- **Desktop**: ≥ 1024px — full three-column layout
- **Tablet**: 768–1023px — right rail collapses, left rail stays
- **Mobile**: < 768px — both rails collapse, hamburger menu, FAB compose, bottom tab bar appears

---

## Copy & voice

The product voice is **editorial, considered, slightly slow**. Hallmarks:
- Mono uppercase labels for system / structural elements (BOARD · #PHILOSOPHY, FROM A FOLLOW)
- Serif body in Traditional Chinese / Newsreader English
- Italic muted text for meta / asides / "why this post" subtitles
- No exclamation marks. No "Awesome!" or "🎉". Quiet confidence.
- Never use the words "post" / "share" / "like" in UI copy — use **發文 · 共鳴 · 回覆**

---

## Out of scope (don't build)

- Stories / status / ephemeral posts
- Direct messaging (DMs) — not designed yet
- Push notification settings detail — placeholder only
- Encryption ceremony details — high-level only

---

## Files in this bundle

| File | Use |
|---|---|
| `README.md` | This document |
| `Elix Forest Letter.html` | **Authoritative color palette + how it applies to feed** — use for all colors |
| `Elix Web.html` | Web design reference (7 views × 3 breakpoints) — apply Forest Letter palette |
| `Elix Screens.html` | iOS app design reference (20 screens) — apply Forest Letter palette |
| `Elix Brand System.html` | Earlier brand-system reference — useful for logo + app icon studies |

To inspect any file, open it in a modern browser. All files are self-contained.

---

## Open questions / decisions deferred

1. **Murmur audio storage** — local-only? Or relay-stored? Designs assume relay-stored with E2E.
2. **DM surface** — Not designed yet. Consider whether DMs exist or if "私訊" routes through circle.
3. **Moderation** — No moderation UI designed. Likely board-level admin only.
4. **Onboarding key recovery** — Encrypted backup is offered but flow not fully designed.
5. **Web push** — Mobile web notifications design pending.
