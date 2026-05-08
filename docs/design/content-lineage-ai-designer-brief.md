# Content Lineage And AI Assistance Designer Brief

> Date: 2026-05-08  
> Product: Ansible / Tris-Aura  
> Audience: Product designer, interaction designer, UI designer  
> Design scope: Manual content transformation, AI assistance setup and review,
> Murmur / Note / Discussion workflows, and privacy-safe lineage visibility.

## Purpose

Ansible is evolving from a forum-style app into a local-first thinking and
discussion tool. A user's rough thought should be able to move through several
clear product modes:

- `Murmur`: quick private capture.
- `Note`: structured private or semi-public writing.
- `Post`: ordinary forum message or reply.
- `Discussion`: public, accountable debate or topic surface.

The design challenge is not to add four isolated tabs. The interface should make
it easy to capture a thought, refine it, understand where it came from, choose
whether AI may help, review every generated output, and only publish after
explicit consent.

## Current Product Context

The existing app is a Flutter app with a dark, forum-like shell. It currently
supports boards, threads, posts, reactions, following feeds, wallet / credential
flows, sync settings, and local database storage.

Engineering has already implemented the local content foundation:

- Local data model for `ContentItem`, mode metadata, lineage relations,
  transformation jobs, context packs, summary jobs, projections, and provider
  configs.
- Repository layer for Drift and in-memory tests.
- Domain service for manual `Murmur -> Note` and `Note -> Discussion`.
- Local lineage projector for showing source and derived content.

Not yet designed or fully built:

- AI provider setup and privacy consent flows.
- Murmur, Note, and Discussion screens.
- Transformation and summary review UI.
- Source boundary disclosure before AI calls.
- Phone-safe navigation and compact layout.
- Public sync UI for discussions and public lineage.

## Product Principles

1. **Private by default.** Murmurs and notes start private and local-only.
2. **Review before creation or publication.** AI output never creates content or
   publishes automatically. The user must accept, edit, discard, or save.
3. **Lineage is visible but calm.** Users should understand "this note came from
   these murmurs" or "this discussion came from this note" without seeing a
   developer-style graph by default.
4. **Publishing is a threshold.** Moving a private note into a public discussion
   must feel meaningfully different from saving a private draft.
5. **AI provider choice is user-owned.** Users can use manual mode, OpenAI-style
   providers, or local HTTP providers. API keys are stored in secure device
   storage, not in the content database.
6. **Legacy forum behavior must remain recognizable.** Existing board, thread,
   and post workflows should not feel broken while the new modes are introduced.

## Primary Users

### Thought Capturer

Captures fragments quickly, mostly private. Needs a low-pressure entry point,
fast save, and confidence that rough thoughts are not public.

### Writer / Synthesizer

Turns murmurs into notes, edits structure, compares sources, and uses AI as an
assistant. Needs review controls, source context, and easy editing.

### Discussion Contributor

Projects a polished note into a public discussion or replies in an existing
discussion. Needs clear ownership and publication boundaries.

### Privacy-Sensitive User

May use local AI or manual mode only. Needs transparent source-boundary language,
provider status, and explicit consent before private content leaves the device.

## Information Architecture To Explore

Designer should propose a navigation model that supports both existing forum use
and new content modes.

Required destinations:

- Home / Feed: existing board and following feed behavior.
- Murmurs: quick private capture list.
- Notes: private workspace for structured drafts.
- Discussions: public or publish-ready discussion surfaces.
- Wallet / Identity: existing credential and identity flows.
- Sync / Settings: existing sync settings plus AI provider settings.

Recommended direction:

- Keep Home / Feed as the default landing experience for current users.
- Add mode navigation for Murmurs, Notes, and Discussions as first-class app
  destinations.
- On phones, use compact navigation that does not rely on a fixed sidebar.
- On desktop/tablet, support a denser workspace layout with a source panel,
  editor/detail panel, and review/metadata side panel.

## Core Flows

### Flow 1: Quick Murmur Capture

Goal: Capture a thought in seconds.

Required behavior:

- Entry point available from main navigation or a persistent compose action.
- Input limit: 500 characters.
- Default state: private and local-only.
- Optional fields: tone, private tags, sensitive flag.
- Save should return the user to the prior context or keep them in capture mode
  depending on the interaction pattern.

Designer should define:

- Quick capture surface: sheet, inline composer, or dedicated screen.
- Empty state for no murmurs.
- Over-limit state.
- Sensitive/private visual treatment.

### Flow 2: Murmur To Note

Goal: Select one or more murmurs and turn them into a structured note.

Required behavior:

- User can select one or more source murmurs.
- User can create manually without AI.
- If AI is available, user may ask for a draft, but must review before accepting.
- Accepting creates a note and lineage relations from the note to each murmur.

Key UI moments:

- Source selection.
- Draft generation or manual composition.
- Review screen with source list, proposed note title/body, edit, discard, and
  accept controls.
- Confirmation that the note remains private by default.

### Flow 3: Note Workspace

Goal: Write, edit, and inspect a structured private note.

Required behavior:

- Show title, body, summary, thesis or outline affordances if useful.
- Show linked source murmurs in a lightweight lineage panel.
- Support transforming or projecting the note.
- Default visibility should read as private/unlisted, not public.

Designer should define:

- Editor layout.
- Linked source panel behavior on phone and desktop.
- Autosave or explicit save affordance.
- Difference between ordinary save, AI-assisted rewrite, and project to
  discussion.

### Flow 4: Note To Discussion Projection

Goal: Turn a private or author-owned note into a public discussion.

Required behavior:

- User chooses to project a note into a discussion.
- UI explains that public discussions have narrower edit/delete rights.
- User must acknowledge ownership/publication transfer before creation.
- Accepting creates a discussion, a projection record, and a `projectedFrom`
  lineage relation.
- A compatibility thread is created so legacy forum behavior still works.

Key UI moments:

- Pre-publish review.
- Ownership transfer acknowledgement.
- Public visibility indicator.
- Final discussion preview.

Designer should make this feel more consequential than saving a draft.

### Flow 5: AI Provider Setup

Goal: Let users configure AI only when they need it, without blocking manual use.

Required behavior:

- First AI action opens provider setup if no provider is configured.
- User can choose:
  - Manual / no network.
  - OpenAI-compatible provider.
  - Local HTTP provider for LAN or self-hosted models.
- Provider setup includes provider type, base URL when needed, model name, API
  key input, test connection, save, and continue.
- Successful setup returns to the original action.
- API key value should be framed as stored securely on-device.

Designer should define:

- First-use setup sheet.
- Provider settings screen.
- Test connection success/failure states.
- How to show active provider status during AI actions.

### Flow 6: Privacy Boundary Before AI Calls

Goal: Prevent accidental private-content disclosure to remote providers.

Required behavior:

- AI reads a fixed context pack, not live database rows.
- Context pack can be public-only, contains private content, or contains
  sensitive content.
- Remote providers cannot receive private or sensitive context unless the user
  explicitly approves that one request.
- Local/manual providers can be shown as safer options for private context.

Required disclosure content:

- What sources are included.
- Whether private or sensitive content is included.
- Which provider will receive the context.
- Whether the action is local-only or remote.
- Clear proceed/cancel controls.

### Flow 7: Transformation Review

Goal: Keep AI assistance review-only.

Required behavior:

- Show generated title/body or structured output.
- Show source boundaries and provider used.
- User can edit before accepting.
- User can discard without creating content.
- Accept action creates the target content and lineage.

Designer should define:

- Review sheet or full-screen review mode.
- Diff or source comparison treatment.
- Error state for failed AI generation.
- Loading state that does not imply content has been created.

### Flow 8: Summary Review And Save As Note

Goal: Summarize a discussion, feed, board, or lineage and optionally save it as a
private note.

Required behavior:

- Summary result is local-only by default.
- User can review, edit, discard, or save as private note.
- Summary should show source boundaries and included/excluded scope.
- Summary should not publish automatically.

Potential summary types:

- Discussion summary.
- Following feed digest.
- Board digest.
- Lineage summary for a note/discussion.

## Required Screens And Components

### Screens

- Murmur list and quick capture.
- Note workspace.
- Discussion detail.
- AI provider settings.
- Optional summary history or saved summaries view.

### Sheets / Modals

- AI provider setup sheet.
- Source-boundary disclosure sheet.
- Transformation review sheet.
- Summary review sheet.
- Lineage inspector sheet.
- Ownership transfer acknowledgement dialog.

### Shared Components

- Content mode switcher or navigation.
- Visibility badge: private, unlisted, public.
- Local-only / sync status indicator.
- Provider status chip.
- Source boundary summary row.
- Lineage mini-list.
- Review action footer: discard, edit, accept/save.
- Error banner for provider/network/privacy rejection.

## States To Design

For each key screen or sheet, include:

- Empty state.
- Loading state.
- Error state.
- Offline state.
- Unsaved changes state.
- AI unavailable state.
- Provider not configured state.
- Private content blocked for remote provider.
- Compact phone layout.
- Desktop/tablet layout.

## Content And Copy Guidance

Use direct product language. Avoid technical database terms in the UI.

Recommended terms:

- "Murmur" for quick private capture.
- "Note" for private structured writing.
- "Discussion" for public debate/topic.
- "Sources" or "Linked sources" instead of "relations".
- "Created from" instead of "expandedFrom".
- "Projected from" can appear in advanced lineage UI, but ordinary users should
  see "Published from note" or "Started from note".
- "This may send private content to [provider]" for remote AI disclosure.
- "Save as private note" for summaries.

Avoid:

- "TransformationJob".
- "ContextPack".
- "Drift".
- "MST".
- "Lexicon record".
- "local_only" or raw sync flags.

## Privacy And Safety Requirements

The UI must make these guarantees understandable:

- Murmurs are private by default.
- Notes are private or unlisted by default.
- Discussions are public by default.
- AI output is never accepted automatically.
- Remote AI calls require disclosure when private or sensitive sources are
  included.
- API keys are not shown after saving, except through a replace/remove control.
- Public projection requires acknowledgement.
- Deleting or editing public discussion content may have narrower behavior than
  editing a private note.

## Visual Direction

The app should feel like a serious local-first knowledge and discussion tool,
not a marketing site.

Preferred qualities:

- Quiet, dense, readable, and work-focused.
- Strong hierarchy between capture, writing, review, and publication.
- Clear privacy and sync indicators without alarmist visuals.
- Comfortable long-form editing.
- Phone layouts that prioritize one task per screen.
- Desktop layouts that use space for source context and review panels.

Avoid:

- Decorative landing-page composition.
- Large hero sections inside the app.
- UI cards nested inside other cards.
- Making AI feel magical or automatic.
- Treating private capture like a public posting flow.

## Designer Deliverables

Please provide:

- Information architecture proposal.
- User flow diagrams for the eight core flows above.
- Low-fidelity wireframes for phone and desktop.
- High-fidelity designs for the primary screens and review sheets.
- Component inventory with states.
- Copy recommendations for privacy and ownership transfer moments.
- Interaction notes for source selection, review, accept, discard, and provider
  setup.
- Responsive behavior notes for phone, tablet, and desktop.

## Acceptance Criteria For Design Review

The design is ready for engineering planning when it answers:

- Can a user capture a private murmur in under a few seconds?
- Can a user understand that Murmur, Note, Post, and Discussion are different
  modes, not just filters?
- Can a user transform murmurs into a note without AI?
- Can a user configure AI only when needed and return to the original action?
- Can a user see what sources AI will receive before a remote call?
- Can a user review and edit AI output before accepting it?
- Can a user understand that projecting a note into a discussion is public and
  changes ownership expectations?
- Can legacy forum users still find boards, threads, posts, and following feed?
- Does the design work on phone width without cramped sidebars or hidden primary
  actions?

## Engineering Status Snapshot

Completed:

- Local content schema.
- Repository interfaces and Drift / in-memory implementations.
- Manual Murmur to Note domain flow.
- Manual Note to Discussion projection domain flow.
- Local lineage projector.

Next engineering phases:

- Finish legacy compatibility verification.
- Build AI provider boundary and privacy policy.
- Build provider setup and review UI.
- Build Murmur, Note, Discussion, and summary screens.
- Add public sync validation and integration QA.
