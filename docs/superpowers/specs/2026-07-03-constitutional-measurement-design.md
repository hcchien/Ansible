# Constitutional Measurement — Aggregate Product Pulse

> Status: implemented 2026-07-03 (`AnsibleRelay.ProductPulse`, sampled by the
> Metrics poller onto the existing Prometheus `/metrics`).
> Answers PM review action #7 / ROADMAP "privacy-preserving product metrics":
> without DAU/retention/board-activity aggregates every priority is a guess,
> but the constitution restricts analytics.

## Problem

Launch decisions need three numbers — are people arriving (activation), do
they come back (retention), is the forum alive (board activity) — while the
constitution forbids surveilling users: no client telemetry, no behavioral
tracking, no per-user analytics stores.

## Design: measure the SERVICE, not the user

Every series is an aggregate `COUNT` over data the relay already holds for
its core function (the signed op log, DID accounts). Nothing new is
collected; nothing per-user is emitted. The client sends zero analytics.

| Series | Type | Meaning |
|---|---|---|
| `elix_registered_dids` | gauge | DID accounts on this relay |
| `elix_active_authors{window}` | gauge | distinct authors with ≥1 op in 1d/7d/28d |
| `elix_active_boards{window}` | gauge | distinct boards with thread/post ops in window |
| `elix_new_authors{window="7d"}` | gauge | authors whose FIRST op is inside the window (activation) |
| `elix_returning_authors{window="7d"}` | gauge | 7d-active authors whose first op predates the window (retention) |

Derivable in Grafana/PromQL: weekly retention ratio =
`elix_returning_authors / (elix_returning_authors + elix_new_authors)`;
growth = `delta(elix_registered_dids[7d])`.

Sampling: every 20th metrics-poller tick (default 15s × 20 = 5 min) — the
COUNT DISTINCT scans are deliberately kept off the request path and off the
per-scrape path.

## Known limits (accepted)

- **Author-activity ≠ reader-activity.** Pure lurkers are invisible — by
  design: counting reads would require request-level user tracking, which
  the constitution forbids. Delta-pull request counts
  (`relay_delta_requests_total`) remain the coarse read-side signal.
- Windows are computed from `ops.received_at` (no index yet); at genesis
  scale this is fine, and the 5-minute cadence bounds the cost. Add a
  `received_at` index before the op table reaches millions of rows.
- Per-relay only; multi-relay aggregation (if ever) sums gauges — still no
  per-user data crosses relays.

## Constitution Review

- **No new collection**: all inputs (`ops`, `did_accounts`) already exist
  for sync/identity; this feature only counts rows.
- **No per-user output**: every exported number is a population aggregate;
  no DID, handle, or board id appears in a label or value. Window labels
  (1d/7d/28d) are the only dimensions.
- **No client involvement**: zero app-side code; users cannot be
  distinguished by their metrics footprint because they have none.
- **Private content untouched**: ops counted are the relay-visible
  (relayable) ops it already stores; content fields are never read except
  the already-public `boardId` for the board-activity count.
- Base Rule "send private content to analytics" — not triggered: no
  content leaves the relay; `/metrics` exposes counts only.
