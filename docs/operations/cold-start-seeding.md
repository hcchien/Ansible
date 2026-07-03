# Cold-Start Seeding Runbook（冷啟動）

> PM review 2026-06-12 P0: "Discover/feed are built but the day-one network
> is empty; without seeding, launch = ghost town." 行銷策略書 v1 lists 種子內容
> as one of the three launch prerequisites (with 分享外連 and 身分復原, both
> shipped). This runbook is the operations half; the engineering half is
> `ansible_node/app/tool/seed_genesis.dart` plus the app's first-run
> auto-subscription.

## What ships in the product

1. **Genesis boards + opening threads** — `tool/seed_genesis.dart` creates
   them on a relay with a real founder identity (same signed-intent and
   signed-op wire contracts as the app; idempotent per board title).
2. **Default subscriptions** — a fresh install auto-subscribes the relay's
   top 3 featured boards once (`HomeShell._ensureDefaultSubscriptions`,
   prefs-flagged; unsubscribe sticks).
3. **Guided first session** — the empty timeline walks new users through
   訂閱看板 → 追蹤一個人 → 發第一則貼文.

The relay advertises featured boards via `GET /api/v1/discovery`
(`featured_boards`), which both the app's first-run block and the default
subscriptions read — seeding the relay is enough; no app release needed to
change the genesis set.

## Launch sequence

```bash
cd ansible_node/app

# 1. Create the founder + genesis boards + opening threads (dev relay):
RELAY_BASE=https://relay-dev.elix.cool \
  dart run tool/seed_genesis.dart founder
# → prints SEED hex. Store it in the team password manager; every future
#   run MUST pass --seed=<hex> to keep publishing as the same founder.

# 2. Custom board set (optional): edit a JSON file and pass --boards=
#    [{"title": ..., "description": ..., "min_post_tier": null,
#      "opening_thread": ...}, ...]

# 3. Verify: the boards appear in
curl -s https://relay-dev.elix.cool/api/v1/forum-host/boards | jq '.boards[].title'
```

The built-in genesis set (4 boards): 大廳, 公共討論（真人版, `verified_human`
gate — the flagship promise made visitable), 工具與工作流, 讀書會.

## The part tooling cannot do (owner needed)

- **Recruited founding posters** — 5–10 people committed to posting/replying
  in each genesis board for the first 2–4 weeks. 行銷策略書: source them from
  the civic-tech seed community (可信度層「來自台灣公民科技前線」).
- **Posting cadence** — the founder account + founding posters keep every
  genesis board's latest activity under ~48h old during the launch window.
- **Announcements** — the relay discovery payload also carries
  `announcements`; use them for launch-week welcome/context.

## Constitution note

Seeded content is ordinary signed content by real identities — no synthetic
accounts posing as organic users, no unlabeled operator content. The founder
account should say it is the founding/team account in its profile.
