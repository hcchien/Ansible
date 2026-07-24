# Board Identity Migration Design

> Status: implementation plan
> Date: 2026-07-24
> Scope: Forum Host, Relay publication, AppView, web, mobile, sync, federation

## Decision

`title` is display-only and `slug` is a mutable, human-readable route alias.
Neither is board identity. Each Forum Host assigns a monotonically increasing
PostgreSQL sequence value as its immutable `board_id`. The globally scoped
identity is the pair `(forum_host_canonical_uri, board_id)`.

All new APIs, signed publication operations, moderation requests, capability
requests, AppView feeds, sync projections, and canonical board URLs use the
canonical `board_id`. A slug URL resolves to a board only as a backwards-
compatible alias and redirects to the canonical URL.

## Compatibility And Migration

1. Add `board_id` as an identity-backed bigint to `forum_host_boards`; backfill
   every existing board, and expose it as a decimal string over JSON.
2. Preserve the existing `hosted_board_id` as a legacy storage key while
   first-party clients migrate. Record every old hosted ID and slug in a board
   alias table with an explicit alias kind.
3. Resolve aliases only at the Relay boundary. The resolver must return one
   board or fail; no suffix, substring, or SQL wildcard matching is allowed.
4. Add an AppView board-alias projection supplied by the Forum Host. Existing
   feed rows are re-keyed to canonical `board_id`; new rows are canonical at
   ingest. AppView must not infer identity from an arbitrary local ID prefix.
5. New web/mobile clients use canonical `board_id` for routes, publication,
   moderation, capability, private-board, sync, and sharing. They may read a
   slug URL during the transition.
6. Once every supported client has migrated and the AppView re-key job has
   completed, deprecate legacy writes. Retain alias reads for old shared links
   until a separately announced sunset date.

## Contract

```json
{
  "board_id": "42",
  "slug": "2026",
  "title": "2026 九合一選舉",
  "canonical_board_uri": "https://forum.example/boards/42"
}
```

`board_id` is serialized as a decimal string so JavaScript and other clients
cannot lose precision. It is host-scoped; consumers require the canonical host
URI when an identity crosses a Forum Host boundary.

## Constitution Review

1. **Identity / credential:** no user identity or credential changes.
2. **Data leaving device:** publication continues only on the user-selected
   Relay/Forum Host path; only an opaque board identifier changes.
3. **Minimum claim:** board selection requires only host-scoped `board_id`.
4. **Sensitive data:** no legal identity, assertions, keys, biometric material,
   or new personal data is introduced.
5. **Trust / access / moderation:** policy semantics are unchanged, but every
   board-scoped decision becomes unambiguous and remains reason-coded.
6. **Personhood:** no binding or duplicate-prevention mechanism is changed.
7. **Exit / migration:** legacy IDs and slug links remain resolvable during the
   announced transition; canonical URIs make host migration explicit.
8. **External hosts:** the canonical host URI remains part of cross-host board
   identity; host compliance representation remains unchanged.

## Verification

- Board titles containing Chinese, whitespace, punctuation, and identical text
  receive distinct sequence IDs.
- A slug collision creates a distinct alias but never changes an existing ID.
- Legacy ID and slug links resolve to the same canonical board.
- Cross-host `board_id = 42` values do not collide.
- AppView returns only records explicitly mapped to the requested canonical
  board ID.
- Web and mobile publication, moderation, capabilities, sync, and sharing use
  canonical IDs.
