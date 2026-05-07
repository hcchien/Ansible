# Content Lineage And Transformation Design Spec

> Status: Draft for review  
> Date: 2026-05-06  
> Scope: Tris-Aura App, `ansible_core/store`, `ansible_core/vc`,
> `ansible_node/app`, and `ansible_relay/phoenix`

## Goal

Add a complete content lineage and transformation architecture to Ansible so a
single thought can move across four product modes:

- `murmur`: compact, low-pressure capture.
- `note`: authored, structured private or semi-public writing.
- `post`: ordinary forum message or reply.
- `discussion`: public, structured debate surface.

The goal is not to add four tabs over the current post feed. The system must
store the source and transformation history of content, support human-reviewed
AI transformation jobs, and make ownership changes explicit when private or
author-owned content is projected into public discussion.

## Existing Context

Ansible is currently local-first. The Flutter app stores boards, threads, and
posts in Drift SQLite, then signs and syncs ops or Lexicon records through the
relay.

Current shape:

- `Boards` group public forum areas.
- `Threads` represent discussion topics under boards.
- `Posts` represent thread root content and replies.
- `LexiconPost` publishes `io.trisaura.post` records through XRPC.
- The relay validates active DIDs and stores signed records as append-only ops.

Aleth has two relevant layers:

- The implemented layer has lightweight `murmurs` and `posts.kind = post/note`.
- The product target has `murmur -> idea/note -> discussion` transformation,
  lineage, review, and ownership transfer.

Ansible should adopt the target product model while preserving its local-first
architecture.

## Non-Goals

- Do not port Aleth's Go content service or GraphQL gateway as-is.
- Do not replace Drift SQLite with a server-first content database.
- Do not require an LLM provider before users can create content manually.
- Do not auto-publish AI output.
- Do not implement a full debate graph renderer in the first implementation
  phase.
- Do not make all murmurs public by default.
- Do not block existing board/thread/post behavior while migration is in
  progress.

## Design Decision

Introduce an Ansible-native `ContentItem` model with mode-specific extension
tables and explicit lineage tables.

Existing `Threads` and `Posts` become compatibility projections over the new
content model during migration:

- A discussion maps to a public topic and can create or reference a `Thread`.
- A post maps to a `ContentItem(mode = post)` and may reference a discussion,
  thread, parent post, or discussion node.
- Existing UI can continue reading `Threads` and `Posts` until the new
  projections are complete.

This avoids a big-bang rewrite and keeps Ansible local-first, while giving
Murmur, Note, Post, and Discussion the same lineage and transformation base.

## Domain Terms

- **Content Item:** The canonical record for user-authored content.
- **Mode:** The product shape of a content item: `murmur`, `note`, `post`, or
  `discussion`.
- **Subject:** A topic, question, issue, or theme shared by related content.
- **Content Relation:** A durable edge between two content items.
- **Lineage:** The complete graph of source, derived, projected, forked, or
  referenced content.
- **Transformation Job:** A reviewable operation that turns one or more source
  content items into a target draft or projection.
- **AI Provider:** A user-selected model source used for summaries and
  transformations.
- **Context Pack:** A fixed, privacy-checked snapshot of content passed to an
  AI provider for one task.
- **Summary Job:** A reviewable operation that summarizes a feed, board,
  discussion, or lineage graph into a local result.
- **Projection:** A special transformation where author-owned content becomes a
  public discussion.
- **Discussion Node:** A structured claim, question, rebuttal, evidence, or
  summary inside a discussion.
- **Ownership Policy:** The edit, delete, comment, fork, and moderation rules
  that apply to a content item.

## Product Modes

### Murmur

Purpose:

Capture short thoughts, observations, questions, and fragments without forcing
forum-level structure.

Behavior:

- Default visibility is `private`.
- Length limit is 500 characters.
- Can be created quickly from the main app.
- Can be grouped by tags, subject, or semantic clustering later.
- Can be transformed into a note.
- Deletion and editing stay under author control unless projected elsewhere.

Initial metadata:

- `tone`: `note`, `question`, `intuition`, or `reaction`.
- `sourceType`: `typed`, `voice`, or `import`.
- `privateTags`: local-only tags.
- `isSensitive`: local visibility warning flag.

### Note

Purpose:

Hold authored, structured writing that belongs to the creator. This is the
Ansible name for Aleth's "Idea" layer.

Behavior:

- Default visibility is `private` or `unlisted`.
- Can link to multiple source murmurs.
- Can be edited as a durable draft.
- Can be projected into a discussion after explicit review.
- Can be published as a normal post when the author does not want public
  discussion semantics.

Initial metadata:

- `thesis`: optional one-sentence claim.
- `outlineJson`: structured outline.
- `summary`: generated or author-written summary.
- `assistantPersona`: transformation preference used for drafts.

### Post

Purpose:

Represent ordinary forum messages and replies. This keeps today's product
behavior available while the richer model is introduced.

Behavior:

- Usually belongs to a thread or discussion.
- Can be a reply to another post.
- Can support or rebut a discussion node later.
- Uses existing reactions and post rendering.

Initial metadata:

- `threadId`: compatibility pointer.
- `parentPostId`: reply pointer.
- `replyToUri`: optional Lexicon/AT-URI pointer.

### Discussion

Purpose:

Represent public, accountable debate. A discussion is more structured than a
flat thread and may be derived from a note.

Behavior:

- Default visibility is `public`.
- Creation from a note requires an ownership-transfer acknowledgement.
- Edit/delete rights narrow after publication.
- Can have discussion nodes with stance and node type.
- Can be forked into another discussion.

Initial metadata:

- `discussionShape`: `thread`, `stance_map`, or `debate_cards`.
- `participationPolicy`: `read_only`, `comment`, or `debate`.
- `forkPolicy`: `disabled`, `allowed`, or `encouraged`.
- `consensusState`: `none`, `emerging`, `contested`, or `stable`.

## Data Model

### Content Items

`content_items` is the canonical content table.

Fields:

- `content_item_id`: stable local UUID.
- `author_did`: DID of the author.
- `subject_id`: optional subject pointer.
- `mode`: `murmur`, `note`, `post`, or `discussion`.
- `title`: optional title.
- `body`: canonical body text or markdown.
- `status`: `draft`, `active`, `archived`, `removed`, or `rejected`.
- `visibility`: `private`, `unlisted`, or `public`.
- `published_at`: nullable publication timestamp.
- `created_at`: UTC timestamp.
- `updated_at`: UTC timestamp.
- `is_deleted`: soft-delete marker.
- `local_only`: true when the item must not sync.

Indexes:

- `(mode, visibility, status, updated_at DESC)`.
- `(author_did, updated_at DESC)`.
- `(subject_id, mode, updated_at DESC)`.

### Mode Extension Tables

`murmur_metadata`

- `content_item_id`.
- `tone`.
- `source_type`.
- `private_tags_json`.
- `is_sensitive`.

`note_metadata`

- `content_item_id`.
- `thesis`.
- `outline_json`.
- `summary`.
- `assistant_persona`.

`post_metadata`

- `content_item_id`.
- `thread_id`.
- `board_id`.
- `parent_post_id`.
- `reply_to_uri`.

`discussion_metadata`

- `content_item_id`.
- `thread_id`.
- `discussion_shape`.
- `participation_policy`.
- `fork_policy`.
- `consensus_state`.

### Subjects

`subjects` groups related content across modes.

Fields:

- `subject_id`.
- `title`.
- `slug`.
- `summary`.
- `created_by_did`.
- `created_at`.
- `updated_at`.

Subjects are optional in MVP. The app can create one automatically when a note
is projected into a discussion.

### Content Relations

`content_relations` stores graph edges between content items.

Fields:

- `relation_id`.
- `from_content_item_id`.
- `to_content_item_id`.
- `relation_type`.
- `created_by_did`.
- `created_at`.
- `local_only`.

Relation types:

- `expanded_from`: a note expands one or more murmurs.
- `projected_from`: a discussion is projected from a note.
- `summarized_from`: a note or discussion summary derives from sources.
- `forked_from`: a discussion forks another discussion.
- `supports`: a post or node supports a claim.
- `rebuts`: a post or node rebuts a claim.
- `references`: general citation or source relationship.

Direction convention:

- `from_content_item_id` is the derived or acting content.
- `to_content_item_id` is the source or target content.

Example:

- Note `N1` expanded from murmur `M1`: `from = N1`, `to = M1`,
  `relation_type = expanded_from`.
- Discussion `D1` projected from note `N1`: `from = D1`, `to = N1`,
  `relation_type = projected_from`.

### Transformation Jobs

`transformation_jobs` tracks AI-assisted or manual mode conversions.

Fields:

- `transformation_job_id`.
- `requested_by_did`.
- `target_mode`.
- `provider_type`: `manual`, `local_llm`, `byok`, or `system_llm`.
- `prompt_profile`.
- `status`: `drafting`, `queued`, `running`, `completed`, `failed`,
  `accepted`, or `discarded`.
- `input_snapshot_json`.
- `output_snapshot_json`.
- `error_message`.
- `created_at`.
- `updated_at`.
- `completed_at`.

`transformation_sources`

- `transformation_job_id`.
- `content_item_id`.
- `source_order`.

Rules:

- Jobs may be manual. A manual job still records lineage and review.
- AI output remains a draft until accepted by the user.
- Accepting a job creates or updates a target content item and writes
  `content_relations`.
- Discarded jobs remain in history but create no target item.

### AI Provider Configs

`ai_provider_configs` stores non-secret provider metadata. API keys and tokens
must live in iOS/macOS Keychain through `flutter_secure_storage`, not in Drift.

Fields:

- `provider_config_id`.
- `display_name`.
- `provider_type`: `manual`, `openai_compatible`, `local_http`, or
  `system`.
- `base_url`: nullable endpoint URL.
- `model_name`: selected model name.
- `api_key_ref`: stable Keychain lookup key, never the key value.
- `default_for_transformations`: boolean.
- `default_for_summaries`: boolean.
- `created_at`.
- `updated_at`.
- `is_deleted`.

Rules:

- `manual` provider requires no secret and performs no network call.
- `openai_compatible` uses a Chat Completions compatible request shape.
- `local_http` is for LAN/self-hosted endpoints and can be allowed to process
  private content after explicit user consent.
- `system` is reserved for future first-party public-content summaries and must
  not receive private content.

### Context Packs

`context_packs` stores the exact snapshot sent to an AI provider or used by a
manual transformation.

Fields:

- `context_pack_id`.
- `purpose`: `murmur_to_note`, `note_to_discussion`,
  `discussion_summary`, `following_summary`, or `board_summary`.
- `source_refs_json`: local IDs and public AT-URIs used as sources.
- `snapshot_json`: immutable content snapshot.
- `privacy_level`: `public_only`, `contains_private`, or
  `contains_sensitive`.
- `allowed_remote`: boolean computed by privacy policy.
- `created_by_did`.
- `created_at`.

Rules:

- AI providers read `ContextPack`, not live mutable database rows.
- Context packs are local-only by default.
- Remote providers cannot receive `contains_private` or `contains_sensitive`
  packs unless the user explicitly approves that one request.
- Context packs should be small and task-specific. The app must never send the
  full local database to a model.

### Summary Jobs

`summary_jobs` stores AI-assisted or manual summaries that do not necessarily
create a new content item.

Fields:

- `summary_job_id`.
- `requested_by_did`.
- `context_pack_id`.
- `provider_config_id`.
- `summary_type`: `discussion`, `following`, `board`, or `lineage`.
- `status`: `queued`, `running`, `completed`, `failed`, or `discarded`.
- `result_json`: structured summary result.
- `error_message`.
- `created_at`.
- `updated_at`.
- `completed_at`.

Result shape:

- `summary`: short prose summary.
- `key_claims`: important claims or topics.
- `disagreements`: open disagreements or unresolved points.
- `source_boundaries`: description of what was included and excluded.
- `suggested_actions`: optional next actions such as save to note.

Rules:

- Summary results default to local-only cache.
- A summary can be saved as a note only after explicit user action.
- Public summaries are future appview behavior, not MVP app behavior.

### Projections

`projections` stores author-owned to public-discussion transitions.

Fields:

- `projection_id`.
- `source_content_item_id`.
- `target_discussion_id`.
- `projected_excerpt`.
- `participation_policy`.
- `ownership_transfer_acknowledged`.
- `acknowledged_at`.
- `created_by_did`.
- `created_at`.

Rules:

- Source must be `note` for MVP.
- Target must be `discussion`.
- Projection cannot become active until
  `ownership_transfer_acknowledged = true`.
- Projection creates a `projected_from` content relation.

### Discussion Nodes

`discussion_nodes` stores structured discussion graph nodes.

Fields:

- `discussion_node_id`.
- `discussion_id`.
- `parent_node_id`.
- `author_did`.
- `node_type`: `claim`, `question`, `evidence`, `rebuttal`, or `summary`.
- `stance`: `support`, `oppose`, `clarify`, or `neutral`.
- `body`.
- `created_at`.
- `updated_at`.
- `is_deleted`.

MVP can render discussion nodes as a threaded list. A map or debate-card view
can be added later over the same table.

### Ownership Policies

`ownership_policies` stores mode-specific capability rules.

Fields:

- `content_item_id`.
- `owner_did`.
- `edit_policy`: `owner`, `moderator`, or `locked`.
- `delete_policy`: `owner`, `moderator`, `tombstone_only`, or `locked`.
- `comment_policy`: `closed`, `followers`, `board_members`, or `public`.
- `fork_policy`: `disabled`, `allowed`, or `encouraged`.
- `moderation_policy`: `owner`, `board`, or `community`.
- `updated_at`.

Defaults:

- Murmur: owner edit/delete, closed comments, fork disabled.
- Note: owner edit/delete, closed comments, fork disabled.
- Post: owner edit, tombstone delete, public or board policy comments.
- Discussion: locked or moderator edit, tombstone delete, debate comments,
  board/community moderation.

## Repository Layer

Add repository interfaces in `ansible_core/store`:

- `ContentItemRepository`.
- `ContentRelationRepository`.
- `TransformationJobRepository`.
- `ProjectionRepository`.
- `DiscussionNodeRepository`.
- `OwnershipPolicyRepository`.
- `AiProviderConfigRepository`.
- `ContextPackRepository`.
- `SummaryJobRepository`.

Existing repositories remain:

- `ThreadRepository`.
- `PostRepository`.
- `BoardRepository`.
- `ReactionRepository`.

Compatibility behavior:

- Creating a legacy thread creates a discussion `ContentItem` and a `Thread`.
- Creating a legacy post creates a post `ContentItem` and a `Post`.
- Loading the existing forum can continue from `ThreadRepository` and
  `PostRepository` until a `ContentFeedProjector` replaces it.

## Application Flows

### Create Murmur

1. User opens Murmur mode.
2. App creates a `ContentItem(mode = murmur, visibility = private)`.
3. App creates `murmur_metadata`.
4. If local-only is true, no Lexicon record is created.
5. If user publishes or syncs the murmur, app signs `io.trisaura.murmur`.

### Murmur To Note

1. User selects one or more murmurs.
2. App creates `TransformationJob(target_mode = note)`.
3. App builds `ContextPack(purpose = murmur_to_note)`.
4. If provider is AI, app checks the context pack privacy level before sending
   it to the provider boundary.
5. If remote approval is required, app shows a one-time disclosure listing the
   selected sources.
6. Provider output opens as a reviewable note draft.
7. User accepts, edits, or discards.
8. On accept, app creates `ContentItem(mode = note)` and one
   `expanded_from` relation for each source murmur.

### Note To Discussion With AI Assistance

1. User selects a note or excerpt.
2. App creates `TransformationJob(target_mode = discussion)`.
3. App builds `ContextPack(purpose = note_to_discussion)`.
4. AI output may include a suggested title, opening body, claim list,
   likely rebuttals, and discussion policy recommendation.
5. App shows all output in a projection review screen.
6. User edits the draft and accepts ownership-transfer acknowledgement.
7. App creates the discussion, projection, and public lineage records.

### Discussion Summary

1. User opens a discussion and taps summary.
2. App builds `ContextPack(purpose = discussion_summary)` from visible
   discussion content, posts, discussion nodes, and public lineage.
3. App sends the pack to the selected provider if privacy policy allows it.
4. App stores a `SummaryJob` with structured result JSON.
5. User can refresh, discard, or save the result as a private note.

### Following Or Board Summary

1. User opens Following feed or a board and taps digest.
2. App builds a bounded `ContextPack` using visible items only.
3. App includes source boundaries such as time range, number of posts, and
   excluded private items.
4. App stores the resulting digest as a local `SummaryJob`.
5. User can save the digest as a note or use it as source material for a new
   discussion.

### Create Note Manually

1. User opens Note mode and writes content.
2. App creates `ContentItem(mode = note, status = draft)`.
3. App stores `note_metadata`.
4. User can keep it private, publish as post, or project into discussion.

### Note To Discussion

1. User selects a note or excerpt.
2. App creates `TransformationJob(target_mode = discussion)`.
3. App shows a projection review screen.
4. User selects discussion shape and participation policy.
5. App shows ownership-transfer acknowledgement.
6. On accept, app creates `ContentItem(mode = discussion)`, a `Thread`
   compatibility row, `discussion_metadata`, `projection`, and
   `projected_from` relation.
7. App signs and syncs `io.trisaura.discussion` and
   `io.trisaura.contentRelation`.

### Discussion Reply

1. User opens a discussion.
2. User creates a post reply or structured discussion node.
3. A plain reply creates `ContentItem(mode = post)` and `post_metadata`.
4. A structured reply creates `discussion_node`; for MVP sync it as an
   enriched `io.trisaura.post` with `discussion` and `stance` fields.

### Discussion Fork

1. User chooses fork on a public discussion.
2. App creates a new `ContentItem(mode = discussion)`.
3. App writes a `forked_from` relation to the source discussion.
4. App applies a fresh ownership policy to the new discussion.

## Flutter UI

Add primary mode navigation:

- `Murmur`.
- `Notes`.
- `Discussions`.
- `Wallet/Profile` remains a utility area.

MVP screens:

- `MurmurScreen`: fast capture, 500-character counter, private/sync toggle,
  list by recency.
- `NoteWorkspaceScreen`: draft list, editor, linked murmurs panel, transform
  review state.
- `AiProviderSetupSheet`: first-use provider setup, API key/endpoint entry,
  model name, test connection, and return to the original action.
- `DiscussionFeedScreen`: public discussions, existing board filters, compact
  phone layout.
- `DiscussionDetailScreen`: thread mode first, later stance map/debate cards.
- `LineageInspector`: bottom sheet or side panel showing source and derived
  content graph.
- `TransformationReviewScreen`: source snapshots, generated output, accept,
  edit, discard.
- `SummaryReviewSheet`: summary result, source boundaries, refresh, discard,
  save as note.
- `ProjectionReviewScreen`: note excerpt, discussion policy, ownership warning.

Mobile layout rule:

- No fixed sidebar below tablet width.
- Mode navigation should be bottom navigation or compact segmented control.
- Lineage and board filters should open as sheets on phones.

## Sync And Lexicon

The sync layer must support new record types while preserving existing
`io.trisaura.post`.

New records:

- `io.trisaura.murmur`.
- `io.trisaura.note`.
- `io.trisaura.discussion`.
- `io.trisaura.contentRelation`.
- `io.trisaura.transformation`.
- `io.trisaura.projection`.

Existing records:

- `io.trisaura.post`.
- `io.trisaura.reaction`.
- `io.trisaura.tombstone`.

Local-only behavior:

- Private murmurs and private notes are not synced by default.
- Transformation job input/output snapshots remain local-only unless user
  explicitly exports them.
- Public relations tied to public content can sync.

Relay behavior:

- Validate active DID and commit signature as today.
- Reject records whose `$type` does not match `collection`.
- Validate required fields for new `io.trisaura.*` records.
- Store records append-only through the current op store.
- Future appview can project records into public feeds.

See `docs/protocol/tris_aura_content_lineage_lexicon_v0.1.md` for record
schema details.

## Privacy And Security

- Private content must default to `local_only = true`.
- API keys and provider tokens must be stored in Keychain through
  `flutter_secure_storage`, not in Drift.
- AI provider calls must use source snapshots, not live mutable rows.
- Remote AI calls must show a first-use disclosure and a per-request disclosure
  when private or sensitive content is included.
- The review screen must show source boundaries before accepting output.
- Public projection requires explicit acknowledgement.
- Synced relation records must not reveal private source IDs.
- If a private murmur becomes a source for a public note or discussion, the app
  must either:
  - keep the relation local-only, or
  - ask the user before publishing the relation.

## Migration Strategy

Phase 1: Core local model

- Add Drift tables and entities.
- Add repositories and unit tests.
- Add compatibility projectors between legacy posts/threads and content items.

Phase 2: Flutter MVP

- Add Murmur, Notes, and Discussions navigation.
- Add create/edit/list flows.
- Add lineage inspector.
- Add manual transformation flow without AI dependency.

Phase 3: AI assistance foundation

- Add provider config and Keychain secret storage.
- Add context pack builders.
- Add OpenAI-compatible and local HTTP provider adapters.
- Add summary jobs and review UI.
- Keep all AI output reviewable and local-only by default.

Phase 4: Lexicon and relay

- Add new Lexicon record classes.
- Add signing tests.
- Add relay validation for new collections.
- Sync public content and public lineage.

Phase 5: AI transformation

- Add local-only privacy controls.
- Add Murmur -> Note and Note -> Discussion provider prompts.
- Add discussion and following summary prompt profiles.

Phase 6: Discussion graph

- Add structured discussion nodes.
- Add thread-mode renderer first.
- Add stance map and debate-card projections later.

## Testing

Store tests:

- Create/list/update/delete content items by mode.
- Create relations and query lineage forward/backward.
- Create transformation job, add sources, accept/discard.
- Create context pack from selected murmurs and verify immutable snapshot.
- Reject remote send when context pack contains private content and no consent.
- Store provider config without API key material.
- Store summary job result and save it as note.
- Enforce private local-only defaults.
- Project note to discussion and create compatibility thread row.

Flutter tests:

- Phone layout does not squeeze discussion content.
- Murmur create flow enforces 500-character limit.
- Note accepts selected murmurs and shows lineage.
- First-use AI action opens provider setup and resumes original task after test
  connection succeeds.
- Summary review shows source boundaries and can save a result as a note.
- Projection review requires acknowledgement.
- Lineage inspector renders source and derived edges.

Relay tests:

- Accept valid new `io.trisaura.*` records.
- Reject mismatched `collection` and `$type`.
- Reject missing required fields.
- Preserve existing `io.trisaura.post` behavior.

Integration tests:

- Murmur -> note -> discussion produces expected rows and relations.
- Public projection syncs discussion and public relation.
- Private source relation remains local-only unless explicitly published.

## Deferred Decisions

- `note` is the Ansible product term for Aleth's `idea` concept. A separate
  `idea` mode is not part of this design.
- Structured discussion nodes sync as enriched `io.trisaura.post` records in
  MVP. A dedicated `io.trisaura.discussionNode` collection can be introduced
  after thread-mode discussion proves useful.
- Murmurs remain private/local-only in MVP. Public murmur publishing can be
  added after privacy controls and lineage prompts are proven.
- AI provider configuration starts inside the note workspace. It can move to
  wallet/profile settings once multiple app surfaces use the same providers.

## Recommended First Implementation Slice

Start with local model and manual flows:

1. Drift tables for content items, metadata, relations, transformation jobs,
   projections, and ownership policies.
2. Repository tests.
3. Murmur screen and Note workspace.
4. Manual Murmur -> Note and Note -> Discussion flows.
5. Lexicon extension only after local behavior is stable.

This gives the product the complete architecture without coupling the first
usable version to AI provider reliability or relay schema changes.
