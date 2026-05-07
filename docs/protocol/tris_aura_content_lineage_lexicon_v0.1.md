# Tris-Aura Content Lineage Lexicon v0.1

> Status: Draft for review  
> Date: 2026-05-06  
> Scope: `io.trisaura.*` content records for Murmur, Note, Discussion,
> lineage, transformation, and projection

## Purpose

This document extends `tris_aura_sync_spec_v2.0.md` with records needed for
content lineage and transformation.

The design keeps Ansible local-first:

- Private murmurs, private notes, and transformation snapshots stay local by
  default.
- Public content can be signed and synced as Lexicon records.
- Public lineage can sync only when it does not leak private sources.

## Collections

Existing collections:

- `io.trisaura.post`
- `io.trisaura.reaction`
- `io.trisaura.tombstone`

New collections:

- `io.trisaura.murmur`
- `io.trisaura.note`
- `io.trisaura.discussion`
- `io.trisaura.contentRelation`
- `io.trisaura.transformation`
- `io.trisaura.projection`

Relay rule:

The XRPC `collection` value must match `record["$type"]`. For example,
`collection = "io.trisaura.note"` requires `record["$type"] =
"io.trisaura.note"`.

## Common Fields

All content records use:

- `$type`: collection name.
- `text` or `body`: content body.
- `createdAt`: ISO-8601 UTC timestamp.
- `langs`: optional BCP-47 language tags.

Records that reference other records use AT-URI strings:

```text
at://{did}/{collection}/{rkey}
```

Local-only records may use local UUIDs in Drift, but must not be synced until
they have public AT-URIs or a privacy-safe mapping.

## `io.trisaura.murmur`

Short-form thought capture.

```json
{
  "$type": "io.trisaura.murmur",
  "text": "string, max 500 chars",
  "tone": "note | question | intuition | reaction",
  "sourceType": "typed | voice | import",
  "langs": ["zh-TW"],
  "createdAt": "2026-05-06T10:00:00.000Z"
}
```

Validation:

- `text` is required and must be non-empty.
- `text` must be at most 500 Unicode scalar values.
- `tone` is optional; if present, it must match the enum.
- `sourceType` is optional; if present, it must match the enum.

Privacy:

- Murmurs are local-only by default.
- Public murmur sync is allowed only after explicit user action.
- Private tags and sensitivity flags are not part of this public record.

## `io.trisaura.note`

Authored structured writing.

```json
{
  "$type": "io.trisaura.note",
  "title": "string (optional)",
  "body": "markdown or plain text",
  "thesis": "string (optional)",
  "summary": "string (optional)",
  "outline": [
    {"title": "string", "body": "string (optional)"}
  ],
  "visibility": "unlisted | public",
  "langs": ["zh-TW"],
  "createdAt": "2026-05-06T10:10:00.000Z",
  "updatedAt": "2026-05-06T10:20:00.000Z"
}
```

Validation:

- `body` is required and must be non-empty.
- `visibility` is required for synced notes and cannot be `private`.
- `outline` is optional.

Privacy:

- Private notes are not synced.
- If a note was generated from private murmurs, source relations stay local-only
  unless the user publishes those relations.

## `io.trisaura.discussion`

Public discussion root.

```json
{
  "$type": "io.trisaura.discussion",
  "title": "string",
  "body": "opening claim, question, or context",
  "discussionShape": "thread | stance_map | debate_cards",
  "participationPolicy": "read_only | comment | debate",
  "forkPolicy": "disabled | allowed | encouraged",
  "consensusState": "none | emerging | contested | stable",
  "boardId": "uuid or at-uri (optional compatibility field)",
  "threadId": "uuid (optional compatibility field)",
  "createdAt": "2026-05-06T10:30:00.000Z",
  "updatedAt": "2026-05-06T10:30:00.000Z"
}
```

Validation:

- `title`, `body`, `discussionShape`, `participationPolicy`, `forkPolicy`,
  and `consensusState` are required.
- Discussions are public records.

Ownership:

- A synced discussion means the author accepted public discussion semantics.
- Edit and delete behavior is governed by local/appview policy and tombstone
  records.

## `io.trisaura.contentRelation`

Public lineage edge between content records.

```json
{
  "$type": "io.trisaura.contentRelation",
  "from": "at://did:.../io.trisaura.discussion/rkey",
  "to": "at://did:.../io.trisaura.note/rkey",
  "relationType": "projected_from",
  "createdAt": "2026-05-06T10:31:00.000Z"
}
```

Relation types:

- `expanded_from`
- `projected_from`
- `summarized_from`
- `forked_from`
- `supports`
- `rebuts`
- `references`

Direction convention:

- `from` is the derived or acting record.
- `to` is the source or target record.

Validation:

- `from`, `to`, and `relationType` are required.
- `from` and `to` must be AT-URIs for synced records.
- The relay may validate URI shape but does not need to resolve all targets in
  the first implementation.

Privacy:

- Do not sync a relation if either side points to private local content.
- If a private source is used to create a public target, the app may sync only
  the public target and keep the relation local.

## `io.trisaura.transformation`

Reviewable transformation metadata.

```json
{
  "$type": "io.trisaura.transformation",
  "sourceRefs": [
    "at://did:.../io.trisaura.murmur/rkey"
  ],
  "targetRef": "at://did:.../io.trisaura.note/rkey",
  "targetMode": "note",
  "providerType": "manual | local_llm | byok | system_llm",
  "promptProfile": "string (optional)",
  "status": "accepted",
  "createdAt": "2026-05-06T10:15:00.000Z",
  "completedAt": "2026-05-06T10:16:00.000Z"
}
```

Validation:

- Synced transformations should normally have `status = accepted`.
- `sourceRefs` must not include private local records.
- Input and output snapshots are intentionally excluded from the public record.

Privacy:

- Full `inputSnapshot` and `outputSnapshot` stay in local Drift by default.
- Public transformation records are audit metadata, not AI transcript storage.

## `io.trisaura.projection`

Acknowledged transition from authored note to public discussion.

```json
{
  "$type": "io.trisaura.projection",
  "source": "at://did:.../io.trisaura.note/rkey",
  "target": "at://did:.../io.trisaura.discussion/rkey",
  "projectedExcerpt": "string",
  "participationPolicy": "read_only | comment | debate",
  "ownershipTransferAcknowledged": true,
  "createdAt": "2026-05-06T10:31:00.000Z"
}
```

Validation:

- `ownershipTransferAcknowledged` must be true.
- `source` must point to a synced note.
- `target` must point to a synced discussion.

Privacy:

- Do not sync projection records for private notes.
- If a public discussion was created from a private note, the app must either
  keep projection local or ask the user to publish the source note first.

## Compatibility With `io.trisaura.post`

`io.trisaura.post` remains valid for ordinary posts and replies:

```json
{
  "$type": "io.trisaura.post",
  "text": "string",
  "replyTo": "at://did:.../io.trisaura.post/rkey (optional)",
  "threadId": "uuid-v4 (optional)",
  "discussion": "at://did:.../io.trisaura.discussion/rkey (optional)",
  "stance": "support | oppose | clarify | neutral (optional)",
  "createdAt": "2026-05-06T10:40:00.000Z"
}
```

The `discussion` and `stance` fields are backward-compatible optional fields.
Older clients can ignore them.

## Relay Validation Requirements

The relay should add lightweight validation for new records:

- Require active DID and valid Ed25519 signature, as today.
- Require `collection == record["$type"]`.
- Require fields listed above for each collection.
- Reject private-only fields in public records, including `privateTags`,
  `inputSnapshot`, and `outputSnapshot`.
- Return `422` for invalid fields and `401` for invalid signatures.

The relay does not need to run transformation jobs or understand AI providers.
It stores signed public records and lets appview/indexers project them.

## AppView Projection Requirements

Future appview/indexer behavior:

- Build public discussion feeds from `io.trisaura.discussion`.
- Attach posts by `discussion` or `threadId`.
- Build lineage graph from `io.trisaura.contentRelation`,
  `io.trisaura.transformation`, and `io.trisaura.projection`.
- Ignore relations that point to unavailable private records.
- Keep current board/thread projections working during migration.

## Versioning

This is `v0.1` because it adds optional records without breaking
`io.trisaura.post`.

Breaking changes should use a new collection name or explicit version field,
for example:

- `io.trisaura.discussion.v2`
- `io.trisaura.contentRelation.v2`
