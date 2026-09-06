# Reactions on posts and replies

## Behavior

Web and Flutter Mobile/Desktop use the existing four reaction types: thumbsUp,
happy, sad and angry. Selection and removal are separate from opening the
reaction summary. The summary shows active expression types and counts; its
expanded view groups publicly attributed users by expression. Each signer has
at most one active reaction per target. Switching preserves the reaction id;
removal uses a signed delete; selecting after removal creates a new reaction.
Reply reactions target the post id, not the containing discussion.

Signed Web operations use the existing passkey ceremony and revision checks.
Successful writes remain visible while AppView indexing catches up. Failed
signing must not change the local selection. Public attribution prefers public
display names and handles, with a DID fallback. Migrated DIDs are deduplicated
for presentation without replacing signed provenance.

## Constitution Review

Read the engineering constitution and current compliance review before changes.
This feature uses the user's existing DID and explicit reaction publication
path. It presents the reaction type and already public profile information;
it does not expose credentials, legal identity, private keys or Wallet data.
Local reaction rows stay local unless the existing signing/sync path is chosen.
Additional AppView lookups are limited to public content. Private-board content
must not gain a public distribution path. Trust tiers, ranking, personhood
bindings, host choice and moderation policy are unchanged. Reactions remain
switchable and removable. This review is limited to the feature and does not
claim that the repository's documented hardware custody or host compliance
policy gaps are resolved.

## Verification

- Web projection: insert/update/delete, four expressions, canonical identity
  deduplication, author escaping, anonymous read and authenticated signing.
- Flutter: reply selection/update/delete/reinsert, failed signing preservation,
  per-type people lists and 320-pixel layout; content detail integration.
- Relay: signed web target/type/author validation, immutable targets on edit,
  existing one-active-reaction and cancellation integration tests.
