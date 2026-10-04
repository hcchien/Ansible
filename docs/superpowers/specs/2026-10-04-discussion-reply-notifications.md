# Discussion reply notifications

## Behavior

The device projects a reply notification for a verified incoming comment on a
locally known content item or forum thread authored by any local identity alias.
It also projects later comments on a discussion where that identity has an
undeleted earlier comment. Self-actions and comments predating participation do
not notify. Direct replies and mentions retain priority and existing dedup keys.
Reply preferences apply to live projection and local history reconstruction.
Standalone notifications open the content discussion. Web public forum feeds
apply the same participation rule.

Relay schedules content-free sync wakes for the publicly known target owner,
direct parent author, and active participants. Registered devices must opt into
reply wakes. Existing debounce coalesces a burst. Encrypted private-board
metadata cannot yield public discussion recipients and remains device-local.

## Constitution Review

- Uses existing public DIDs and already authorized published or decrypted data.
- Notifications and read state remain local; pushes contain only a sync hint.
- No legal identity, credential, private key, or private comment content is added
  to distribution, telemetry, or payloads.
- Does not change trust, ranking, posting access, or moderation.
- Existing reply settings allow disabling notifications; deleting a comment
  removes its participation eligibility. No new personhood binding is created.
- Adds no external-host trust reliance. The existing compliance review's key
  custody and external-host policy gaps remain open.

## Verification and limitations

Focused Flutter projection/rebuild/screen tests and Web projection/render tests
cover this change. Relay tests require the repository's local PostgreSQL test
configuration. Notification projection requires locally available target and
comment data; a wake alone is not evidence of delivery or OS banner display.
Release, production delivery, and physical-device background operation require
separate verification. Participant wake lookup decodes active comment operations
from the log; a dedicated indexed projection is future scaling work.
