# Local-first rendering review

## Behavior

The home shell previously awaited remote timeline responses after reading
SQLite, before publishing any view state. Refresh also replaced mounted lists
with a full-page loader. Board detail similarly waited for remote deliberations
and external items, and Discover loaded three remote categories serially.

Home now publishes the local projection first. A single background request
updates an in-memory remote snapshot, then re-reads current local state. Local
refresh finishes without waiting for HTTP. Failed requests retain the previous
snapshot; identity or selected Relay changes invalidate it; late responses
cannot overwrite the new scope's state. Locally edited, private, deleted, or blocked content is checked
when constructing the rendered list. With no local timeline rows, the timeline
alone remains loading until the remote request finishes or times out.

Contact/notification maintenance follows the first local read. Existing relay
subscription-before-history-pull ordering is preserved. Personal content and
forum views are no longer gated on the remote timeline.

Timeline and forum rows keep stable keys and animate changed content for 220 ms.
Unchanged rows retain their state. New ordering waits behind a “Show updates”
action while the reader is scrolled down; removals apply immediately. Explicit
sort/filter changes reset the corresponding list. Reduced-motion settings skip
animations. This does not add a disk cache of Relay-only results.

Board detail renders native local threads before independently refreshing its
remote sections. Discover starts with locally subscribed board projections and
loads people, boards, and posts concurrently, with per-category loading/errors.

## Constitution Review

Reviewed the engineering constitution and its current compliance review before
implementation. This is a read-path and presentation change:

1. Existing local DID and locally stored content remain the identity/data scope.
2. Only the existing public Relay/discovery and configured board-read paths
   run. No new upload, publication, federation, or backup path is introduced.
3. No new identity claim is requested or presented.
4. No raw identity, keys, credential payloads, or biometrics enter the new cache,
   logs, or network payloads.
5. Signature labels, reputation lookup, blocked-author filtering, posting gates,
   board read authorization, and both external-content opt-in gates still run.
6. No personhood binding or duplicate-prevention key is introduced.
7. Existing user controls are retained. Pending visual updates are optional to
   reveal while reading; deletions are not delayed by that presentation buffer.
8. External source selection and compliance handling are unchanged. This change
   does not resolve the repository-wide gaps recorded in the compliance review.

## Production integration

The release is based on current `origin/prod` (`e98dccb1`), preserving the Relay
native-read changes introduced after the older dirty workspace base. Background
fetch uses `socialRelayBaseUrl` and the accepted-follow timeline, without
restoring the removed AppView or explore-fill route. Unrelated dirty files from
the primary workspace are excluded.

## Validation

- Full Flutter static analysis from the clean production worktree: no issues.
- Slow/incomplete HTTP response: local rows appear and local refresh completes.
- Remote success merges without duplicate cards; local edits win over old text.
- Failure retains remote rows; newly private content does not reappear.
- Late response after disposal is ignored.
- Switching Relay clears the previous snapshot and rejects an old in-flight
  response before fetching and displaying the new Relay's result.
- Empty local timeline does not claim to be empty before the remote result.
- Board and Discover local rows appear before independent remote sections finish.
- Row animation, unchanged row identity, reading position, deferred insertions,
  immediate removals, and reduced motion covered by widget tests.
- Offline rendering at 390, 834, and 1280 logical pixels in light/dark appearance.
- Final production focused suite: 39 tests passed (local-first, animation,
  existing swipe/style, Discover subscriptions, forum discovery, and release
  readiness).
- Earlier working-tree `home_shell_sync_test.dart`: 11 passed, 7 failed. An isolated copy of
  the pre-change working tree reproduced the exact same 7 failures: first-run
  discovery, four manual-sync/setup/authorization cases, and two engagement
  count cases. On current prod, first-run discovery passes; the other six remain.
- The clean production full-suite attempt stalled after 805 passed, 16 failed,
  and 1 skipped and was stopped. Failures remain in the nine files recorded for
  1.0.14: `ai_setup_flow_test`, `board_policy_draft_test`,
  `elix_content_sharing_test`, `home_shell_sync_test`, `i18n_compose_path_test`,
  `moderation_rendering_test`, `notifications_screen_test`, `report_flow_test`,
  and `widget_test`. This is not a claim that the full suite is green.

Rendered widget screenshots are generated by setting `LOCAL_FIRST_PREVIEW_DIR`
when running `test/local_first_render_test.dart`. These checks do not measure
physical-device frame timing or establish TestFlight/production availability.
Build and TestFlight delivery evidence is recorded separately from these source
checks.
