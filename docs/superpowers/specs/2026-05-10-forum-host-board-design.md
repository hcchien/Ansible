# Forum Host Board Model Design Spec

> Status: Draft for implementation planning
> Date: 2026-05-10
> Scope: Ansible app, `ansible_core/store`, relay sync, Forum Host server,
> distribution FE, and federation projection flows

## Goal

Clarify ownership and synchronization for discussion boards in a multi-relay
world. Boards that represent public or shared discussion spaces are not local
canonical entities. They are owned by a Forum Host, projected into the local app
for reading and posting, and distributed outward according to host policy.

This spec also distinguishes forum discussion from user-owned personal content:
`murmur` and `note` remain local-first user-owned content that may be projected
to external targets.

## Design Decision

Use a Forum Host ownership model:

- A **Forum Host** owns forums, hosted boards, thread identity, post identity,
  moderation, deletion policy, ordering, permissions, and the distribution FE.
- The app stores **local projections** of hosted boards, threads, and posts.
  Local state is a cache plus draft/write intent state, not canonical forum
  ownership.
- `murmur` and `note` are **user-owned local content**. The app is canonical
  for them and can project public/unlisted items to Forum Hosts, Nostr relays,
  or ActivityPub relay distribution.
- A local-only board is not a discussion board. If the user needs a private
  organizing surface, it should be modeled as a local collection, notebook, or
  workspace, not as a forum board.

## Naming

Use these terms in code and product copy:

| Term | Meaning |
|---|---|
| Forum Host | A server plus distribution FE that owns forums/boards and distributes discussion content. This replaces the overloaded phrase "relay server" for forum surfaces. |
| Hosted Board | A discussion board owned by one Forum Host. |
| Board Projection | The app's local cached representation of a hosted board. |
| Board Subscription | A user's read relationship to a hosted board on a Forum Host. |
| Board Publication Target | A write target for a thread/post or a projected note/murmur. |
| Local Collection | A personal local-only organization container. It is not a forum board. |

`relay server` can still describe protocol infrastructure in Nostr or
ActivityPub contexts. For Ansible discussion surfaces, prefer `Forum Host`.

## Ownership Model

### Forum Discussion

Forum discussion state is host-owned:

- Hosted board identity is assigned by the Forum Host.
- Thread and post identity are assigned by the Forum Host when content is
  accepted.
- The host decides whether a user may create boards, start threads, reply,
  edit, delete, moderate, or mirror content.
- The app may create local drafts and signed write intents, but accepted forum
  state comes back from the host as projection data.

The local app must preserve host identity on every forum projection:

- `forumHostId`
- `hostedBoardId`
- `canonicalBoardUri`
- `hostedThreadId` for forum threads
- `hostedPostId` for forum posts
- `localProjectionId` for local storage and UI references

### Personal Content

Personal content state is user-owned:

- `murmur` and `note` remain local canonical `ContentItem`s.
- Private content stays local.
- Public/unlisted content may be projected outward.
- Projection targets may include Nostr relays, ActivityPub relay distribution,
  or Forum Host boards.

A note projected to a hosted board is not the same entity as the local note. The
local note is canonical; the hosted board receives a projected post or thread
copy with its own host-assigned identity.

## Distribution Topology

```text
Forum reading:
  Forum Host hosted board -> local board projection cache

Forum writing:
  app local draft/write intent -> Forum Host -> accepted thread/post projection

Personal content:
  app-owned murmur/note -> selected projection targets
                     |-> Nostr relays
                     |-> Forum Host hosted boards
                     |-> ActivityPub relay layer
```

Forum Hosts may later federate with each other, mirror to Nostr, or distribute
to ActivityPub. That is host/server behavior and must not change the app's
canonical ownership rules.

Web distribution frontend:

```text
Hosted web account:
  web UI -> Forum Host account/session -> hosted board writes

App-mediated self-custody DID:
  web UI -> relay web-session challenge -> app approval/signature
  web UI -> scoped Forum Host write APIs as approved DID
```

The Forum Host must accept web-originated writes without requiring local app
storage. It must still preserve identity tier and provenance: hosted web accounts
are not the same trust tier as app-approved self-custody DID sessions.

## Create Flows

### Create Hosted Board

Creating a discussion board requires selecting a Forum Host.

Flow:

1. User chooses "Create hosted board".
2. App asks for the Forum Host.
3. App sends a signed create-board intent to that host.
4. Host accepts or rejects the request.
5. On acceptance, host returns `hostedBoardId`, `canonicalBoardUri`, display
   metadata, and permissions.
6. App stores a local board projection and a board subscription/binding.

The app must not create a canonical local forum board without a host.

### Follow Hosted Board

Following a board is host-specific.

Flow:

1. User selects a Forum Host or opens a board URL.
2. App resolves available hosted board metadata.
3. User subscribes.
4. App stores a `BoardSubscription` and local projection.
5. Foreground pull refresh reads host deltas for subscribed boards.

### Create Local Collection

If the user wants a private local organizing surface, the app creates a Local
Collection. It does not sync through forum board logic and does not produce
forum threads/posts.

## Multi-Host Discussion Policy

Use primary-host identity plus cross-post targets. Do not model one shared board
as multi-primary across independent Forum Hosts.

Rules:

- A hosted board has exactly one owning Forum Host.
- A thread/post has exactly one primary Forum Host context.
- The user may cross-post a thread/post to other hosted boards on other hosts.
- Cross-posted copies have independent host-assigned identities.
- UI should show source/target status so users understand copies are not the
  same canonical thread.

This avoids ambiguous moderation, deletion, ordering, and permission semantics.

## Data Model Additions

### ForumHost

Represents a discussion host and distribution FE.

Required fields:

- `forumHostId`
- `displayName`
- `baseUrl`
- `canonicalHostUri`
- `serverKind`: `ansibleForumHost`
- `capabilities`
- `isActive`
- `createdAt`
- `updatedAt`

This may initially wrap or replace `RemoteNode`. The product name should be
Forum Host even if the storage migration keeps a compatibility alias.

### HostedBoardProjection

Represents the local projection/cache of a host-owned board.

Required fields:

- `localBoardId`
- `forumHostId`
- `hostedBoardId`
- `canonicalBoardUri`
- `remoteSlug`
- `localSlug`
- `title`
- `description`
- `permissions`
- `lastSeenCursor`
- `createdAt`
- `updatedAt`
- `isDeleted`

`localSlug` is only for local UI routing and must be disambiguated when another
projection uses the same slug.

### BoardSubscription

Represents the user's read relationship to a hosted board.

Required fields:

- `subscriptionId`
- `forumHostId`
- `hostedBoardId`
- `localBoardId`
- `readEnabled`
- `writeEnabled`
- `syncCursor`
- `retentionDays`
- `createdAt`
- `updatedAt`

This replaces the current assumption that `BoardSyncConfig` can fully describe
board sync.

### BoardPublicationTarget

Represents where a local draft, thread/post, note, or murmur should be written.

Required fields:

- `targetId`
- `localSourceId`
- `sourceType`: `threadDraft`, `postDraft`, `contentItem`
- `forumHostId`
- `hostedBoardId`
- `mode`: `primary`, `crossPost`, `projection`
- `status`: `pending`, `accepted`, `failed`, `rejected`
- `remoteThreadId`
- `remotePostId`
- `error`
- `createdAt`
- `updatedAt`

## Sync Behavior

### Pull

Foreground pull refresh should read from active Forum Hosts and subscribed
hosted boards. It should no longer treat "all active relay state" as a flat
global delta.

Pull input:

- active Forum Hosts
- active board subscriptions
- per-subscription cursor

Pull output:

- upsert hosted board projections
- upsert hosted threads/posts
- update per-subscription cursor
- record rejected/deleted/tombstoned projection state

### Push

Forum writes are explicit write intents:

- Create hosted board intent
- Create thread intent
- Create reply intent
- Edit post intent
- Delete/tombstone intent
- Project note/murmur to hosted board intent

The app can queue intents locally, sign them, send them to the selected Forum
Host, and wait for host acceptance. A local draft remains a draft until the host
returns accepted remote identity.

## UI Requirements

### Forum Host Settings

Terminology update, 2026-06-02: app Sync settings now present the primary
bootstrap/sync endpoint as **Elix Relay** and keep Nostr Relay settings hidden
behind the optional advanced section by default. Forum Host remains the
ownership model for hosted boards, rules, permissions, moderation, and forum
state, but the top-level app setting should not confuse ordinary users by
mixing Forum Host and Relay endpoints.

For hosted boards, the settings surface should still support:

- Add/edit/remove Elix Relay / Forum Host endpoint records.
- Show host capabilities.
- Browse or import hosted boards.
- Subscribe/unsubscribe per hosted board.
- Configure read/write and retention per subscription.

### Create Discussion Surface

Replace local "Create board" for discussion with:

- "Create hosted board"
- required Forum Host selector
- title/description
- host capability/permission feedback

If no Forum Host is configured, show an empty state that explains discussion
boards live on Forum Hosts.

### Create Thread/Post

Thread creation requires a hosted board target. Cross-posting is optional and
advanced:

- primary target: one hosted board
- optional cross-post targets: zero or more hosted boards

The distribution web UI may create threads and replies directly through Forum
Host APIs. If the user is using an app-mediated self-custody session, the host
must verify the relay-issued web session and required scope before accepting the
write. If the user is using a hosted web account, the host must apply the lower
trust tier's rate limits and moderation policy.

### Project Note/Murmur

Visibility controls stay on personal content, but distribution settings should
let users choose Forum Host board targets independently from Nostr/ActivityPub
targets.

## Failure Behavior

- If host board creation is rejected, no hosted board projection is created.
- If a thread/post intent is rejected, the local draft remains local with an
  explicit failed/rejected status.
- If cross-post target A succeeds and B fails, keep per-target status.
- If two hosts expose the same board slug/title, keep both projections and
  disambiguate local slugs and display metadata.
- If a host is offline, preserve queued write intents and last known projection
  data.

## Migration

The current `Board` table can remain temporarily as the local projection table,
but implementation must stop treating it as the canonical discussion board.

Migration phases:

1. Introduce Forum Host terminology and model aliases around `RemoteNode`.
2. Add hosted board projection and board subscription data alongside existing
   `Board` and `BoardSyncConfig`.
3. Move sync pull/push to hosted-board bindings.
4. Rename UI from "server/relay board sync" to Forum Host subscriptions.
5. Split local personal organization into Local Collections if still needed.
6. Deprecate local-only discussion board creation.

## Non-Goals

- Multi-primary shared boards across independent Forum Hosts.
- Local-only discussion boards.
- Treating cross-posted copies as one canonical thread.
- ActivityPub endpoints in the app client.
- Private content federation.
- Treating a hosted web account as equivalent to an app-approved self-custody DID
  session.
- Exporting the app user's DID private key to browser storage.

## Acceptance Criteria

- Docs state that Forum Hosts own forum boards, threads, and posts.
- Docs state that local app boards are projections/caches for hosted forums.
- Docs state that murmurs and notes remain local user-owned canonical content.
- Create-board requirements include a required Forum Host for discussion boards.
- Multi-host publishing is modeled as cross-post/projection targets, not shared
  board synchronization.
- Migration path preserves existing tests while adding new hosted-board
  binding semantics.
- Web-originated forum writes are supported through Forum Host APIs, with
  explicit trust tier and scope enforcement.
