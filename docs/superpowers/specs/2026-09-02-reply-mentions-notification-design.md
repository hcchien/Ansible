# Reply Mentions And Local Notifications

> Date: 2026-09-02
> Status: Implemented design contract
> Scope: Flutter mobile/desktop and Web reply composers, signed Relay
> operations, content-free wake pushes, and local notification projection

## User Experience

- A user composing a forum reply or standalone-content comment can open a
  people picker, search the public AppView profile projection, and insert the
  profile's `@display_name` into the reply. The picker keeps `@handle` visible
  as secondary disambiguation, and duplicate display names gain an inline
  handle suffix when both are selected.
- Selecting a result binds the visible display name to that profile's public DID.
  Typing arbitrary `@text` does not create a recipient because handles are
  presentation data and are not authorization or routing identifiers.
- A signed public reply carries at most ten unique `mentionDids`. The mentioned
  user's device creates a local `mention` notification after syncing the
  verified operation. If wake pushes are enabled, Relay sends only the existing
  content-free `{ "hint": "sync" }` signal.
- Mention notifications have their own preference and open the referenced
  thread/content discussion.
- After publication, an explicitly selected mention is rendered in the accent
  color with a distinct weight/underline and opens that DID's public profile.
  The signed payload stores the exact visible token next to its DID so duplicate
  names and later profile renames cannot redirect the link. Older replies that
  only carry `mentionDids` resolve the current public display name/handle as a
  compatibility fallback.
- On Web, opening the reply composer, selecting a public profile, and sending
  the reply are real interactions rather than a static composer. The browser
  signs the exact `forum.reply` operation with WebAuthn; the payload uses the
  same `mentionDids` field as native clients.
- Web projects mention notifications from public board feeds. Its read state is
  browser-local and never becomes Relay notification/read-state data.

## Protocol And Abuse Boundary

- `mentionDids` contains public DIDs only. The client removes the author DID,
  malformed values, duplicates, and values beyond the ten-recipient limit.
- The optional `mentions` presentation list contains `{did, token}` pairs only
  for those same bounded `mentionDids`. Renderers require the token to occur at
  a mention boundary in the signed body; they never infer a target DID from
  arbitrary display text. Native clients persist these references locally so
  offline/local-first rendering retains the same link target.
- Relay independently applies the same type, self-mention, uniqueness, and
  ten-recipient bounds before scheduling wakes. A signed payload cannot turn a
  single reply into an unbounded push fan-out.
- Private-board mention metadata remains inside the encrypted content envelope.
  It is projected only after an authorized device decrypts the reply; Relay
  does not receive private mention recipients and therefore cannot target a
  wake from that metadata.

## Constitution Review

1. The identity involved is the selected profile's existing public DID; the
   display name, handle, and signed visible token are presentation text only.
2. For public replies, the user already chose the public publication/sync path,
   and the selected public DIDs leave the device as part of that signed op. For
   private boards, mention DIDs remain encrypted with the reply. Web publication
   remains limited to the existing public/unlisted rail and does not add a
   private-board path.
3. The minimum routing/navigation claim is a public DID. The visible token is
   retained only to render the user's explicit selection. No credential or
   trust-tier claim is needed.
4. Raw legal identity, provider assertions, private keys, biometrics, and
   private notification/read state are excluded from op payloads, pushes, and
   logs.
5. Mentions do not change trust tier, ranking, rate limits, access, or
   moderation state. Existing posting and anti-abuse controls still apply.
6. No personhood binding or duplicate-prevention key is created.
7. The author can remove a mention before sending; recipients can disable the
   mention notification category. Local read state remains deletable with the
   existing notification store controls.
8. Public profile search uses the first-party AppView projection. The feature
   does not add reliance on an external host's compliance claim.

The design is compatible with the current compliance review. It does not claim
to close the remaining hardware-key or external-host-policy gaps.
