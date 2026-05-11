# Forum Frontend IA And Visual Design Concept

> Status: Draft for implementation planning  
> Date: 2026-05-11  
> Scope: Distribution frontend information architecture, visual direction,
> app-mediated login presentation, and view-model-to-page mapping

## Goal

Define the first production UI direction for the forum frontend while keeping
the current route skeleton intact.

The frontend should feel like a forum first and a session console second. A
visitor should be able to browse the host, boards, and board content before
they understand the login protocol. App-mediated login becomes prominent only
when the user signs in, posts, replies, or manages sessions.

## Design Decision

Use a forum-first network console concept.

The product stance is forum-first:

- Public reading is the default entry path.
- Boards and board content remain the primary content surface.
- Login is a dedicated flow, not the landing experience.
- Session and trust metadata are visible but do not dominate browsing.

The visual stance is network console:

- Dark technical interface.
- High-contrast relay/session status.
- Compact header controls.
- Clear provenance, trust tier, scopes, and error states.
- Minimal decoration and no marketing-style hero treatment.

The layout stance is command header:

- A strong top header owns app identity, navigation, route context, and session
  status.
- Main content remains single-column or simple grid depending on the page.
- Persistent side rails are avoided for the first implementation.
- Session details live in the dedicated login and sessions pages.

## Route Skeleton

Do not add new routes for this design pass. The UI must use the current frontend
route skeleton:

| Route | Page | Role |
|---|---|---|
| `#/` | Home | Forum host overview, primary board entry points, public reading state |
| `#/boards` | Boards | Board directory and board-level permissions summary |
| `#/boards/:boardId` | Board | Selected board context, thread list, and post action state |
| `#/login` | Login | Dedicated app-mediated login challenge page |
| `#/sessions` | Sessions | Authenticated session, trust tier, scopes, expiry, and revoke actions |
| fallback | Not found | Unknown route or unavailable forum target |

No first-pass routes for diagnostics, profile, thread detail, notifications,
moderation, or settings should be introduced. Those can be represented later by
new specs when the data model supports them.

## Page IA

### Home

Home introduces the Forum Host, not the authentication mechanism.

Content priority:

1. Host identity and availability.
2. Primary board entry points.
3. Public reading capability.
4. Session status in the command header.
5. Lightweight prompt to sign in when the user wants to post.

Home should avoid a marketing hero. The first viewport should look like a
usable forum surface with real board affordances.

### Boards

Boards is a dense directory view.

Content priority:

1. Board title and description.
2. Read/write capability indicators derived from adapter permissions.
3. Thread count or other summary metadata when available.
4. Disabled or gated create actions when the session lacks scope.

The visual treatment should be compact rows or restrained panels, not oversized
cards.

### Board

Board is the primary reading and posting context.

Content priority:

1. Board title and permission state.
2. Thread list or empty state.
3. Create thread action.
4. Scope or login requirement when posting is unavailable.
5. Forum adapter error if the board cannot be loaded.

If a user starts a post while anonymous, the UI should route them to `#/login`
and preserve enough draft or return context for a later implementation. This
spec defines the IA expectation but does not require draft persistence yet.

### Login

Login is a dedicated app-mediated challenge page.

Content priority:

1. Current challenge status: starting, pending, approved, rejected, expired, or
   error.
2. QR payload and deep link when a challenge exists.
3. Requested scopes and expiry.
4. Relay origin and web origin.
5. Clear retry path for rejected or expired challenges.
6. Success state that shows authenticated trust tier before returning to forum
   context.

The Login page must not imply the browser receives DID private keys. It should
state the session as an app-approved browser session through labels such as
`self_custody_did` and `scoped web session`.

### Sessions

Sessions is available only after authentication.

Content priority:

1. Current subject DID or account label.
2. Trust tier.
3. Granted scopes.
4. Expiry.
5. Revoke current session.
6. Error and expired states.

The first implementation can show only the current session if the relay does
not yet expose a full active session list.

### Not Found

Not Found should use the same network-console visual system.

Content priority:

1. Route or resource unavailable message.
2. Link back to Home or Boards.
3. Error taxonomy label when available.

## Command Header

The command header is the central shell component.

Required content:

- Product label: `Forum Relay` or the host display name when available.
- Navigation links from `deriveNavigationItems`.
- Current route title from the app view model.
- Session chip:
  - Anonymous: `Anonymous`, `Read only`, or `Sign in`.
  - Authenticated: short DID/account label and trust tier.
  - Error/expired: compact warning state.
- Primary action:
  - `Sign in` when anonymous.
  - `New thread` when the current page can create a thread.
  - `Revoke` only inside Sessions.

Header controls should stay compact and text should not wrap inside fixed
buttons. On mobile, navigation can collapse into a compact row or menu, but the
session chip must remain visible.

## Visual System

Use a dark network-console palette without turning the whole UI into a one-note
blue theme.

Suggested tokens:

| Token | Use |
|---|---|
| `#0f1720` | Page background |
| `#101c27` | Header and control surfaces |
| `#142230` | Main content panels |
| `#253646` | Borders |
| `#31505b` | Muted dividers and secondary fills |
| `#7dd3c7` | Active session, relay online, primary focus |
| `#f2c14e` | Pending challenge and warning state |
| `#f97066` | Rejected, expired, destructive, or invalid session |
| `#dce7e5` | Primary text |
| `#93a4ad` | Secondary text |

Typography should be compact, readable, and operational:

- Use system fonts for the first pass.
- Page titles: medium weight, not oversized.
- Table/list labels: small but readable.
- Monospace only for challenge IDs, DID fragments, origins, and scope chips.
- Do not use hero-scale type inside forum content.

Component shape:

- 6px to 8px radii.
- Thin borders.
- No nested cards.
- No decorative gradient blobs.
- Clear focus outlines and keyboard states.

## State Mapping

The visual design should map directly to existing frontend view-model fields:

| View model field | UI use |
|---|---|
| `page.title` | Command header route title and page heading |
| `navigation` | Header nav links |
| `session.authenticated` | Session chip and gated actions |
| `session.trustTier` | Authenticated provenance label |
| `session.scopes` | Login and Sessions scope chips |
| `session.expiresAt` | Sessions expiry and login success detail |
| `host` | Home host identity |
| `boards` | Home and Boards directory |
| `board` | Board header |
| `threads` | Board thread list |
| `actions.showLogin` | Header sign-in action |
| `actions.canCreateThread` | New thread button enabled state |
| `actions.canReply` | Reply affordance enabled state |
| `actions.canRevokeSession` | Sessions revoke control |
| `error` | Page-level error banner using taxonomy tone |

## Error Presentation

Use the error taxonomy already defined in the frontend.

Presentation rules:

- Missing scope: show a gated-action message with a sign-in or re-approve path.
- Invalid or expired session: show a header warning and route the recovery
  action to `#/login`.
- Network error: keep current forum context visible and show retry.
- Not found: use the Not Found route surface.
- Rate limited: show wait/retry language and keep the attempted action disabled.

Errors should be understandable to forum readers, with protocol detail available
in compact secondary text.

## Responsive Behavior

Desktop:

- Command header across the top.
- Main content constrained to a readable max width.
- Boards can use dense rows or a two-column grid when there is enough space.

Tablet:

- Header wraps navigation and session chip into two rows if needed.
- Board lists remain scannable.

Mobile:

- Header becomes compact.
- Navigation remains accessible.
- Session chip stays visible.
- Board and thread lists become single-column.
- Login challenge QR/deep-link section remains the main content and avoids
  horizontal overflow.

## Implementation Boundaries

This spec is IA and visual design only. It does not require:

- New routes.
- New relay APIs.
- New forum data fields.
- Thread detail pages.
- Profile pages.
- Moderator/admin surfaces.
- Notifications.
- Persistent draft storage.

The next implementation pass should style and compose the existing route
skeleton around current API, session lifecycle, forum adapter, fixtures, and
integration harness.

## Acceptance Criteria

- UI uses only the current route skeleton.
- First screen is a forum surface, not a login-only screen.
- Command header shows navigation, route title, and session state.
- `#/login` is the dedicated app-mediated challenge page.
- `#/sessions` shows authenticated session lifecycle information.
- Anonymous users can understand what is readable and what requires sign-in.
- Authenticated users can see trust tier, scopes, and expiry.
- Error states map to the frontend error taxonomy.
- Responsive layouts avoid overlapping text and horizontal overflow.
- Integration fixtures can render anonymous, approved, rejected, expired, and
  invalid-session states without new backend dependencies.
