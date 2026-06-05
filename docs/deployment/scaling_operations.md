# Scaling Operations

How to scale the Genesis services after launch, what is already horizontally
scalable, and which env flags turn on each scale feature. Defaults are the
single-instance / lowest-infra path; everything below is opt-in.

## What is stateless / shared now

These services hold no authoritative in-process state — they share PostgreSQL —
so they can run as **N stateless Cloud Run instances** (or a GKE deployment):

- **Relay**: ops are Postgres-backed (`OpStore`); identity verification reads
  through to Postgres (`IdentityCache`); rate-limit checks are ETS (per-instance)
  unless a shared limiter is configured (below).
- **Issuer**: personhood-binding and provider-session stores are Postgres-backed
  when `DATABASE_URL` is set; duplicate-prevention is enforced by DB constraints
  across instances.
- **AppView**: the projection is Postgres; reads can use a replica + cache.

## Enable-at-scale flags

### Relay
| Env | Effect |
|---|---|
| `REDIS_URL` | Shared cross-instance abuse limiter (accurate rate limits behind a load balancer; otherwise per-instance). |
| `LIBCLUSTER_HOSTS` | Comma-separated node names → Erlang clustering (GKE/Presence). Unset = no clustering (Cloud Run scales via shared DB, no distribution needed). |
| `POOL_SIZE`, `DATABASE_SSL` | DB pool size / TLS. |
| `eager_identity_cache` (config) | Opt back into loading all DIDs at boot; default is lazy read-through. |

### Issuer
| Env | Effect |
|---|---|
| `DATABASE_URL` | Postgres personhood + session stores → horizontal scaling (else file-backed, single instance). |

### AppView
| Env | Effect |
|---|---|
| `DATABASE_REPLICA_URL` | Route timeline reads to a read replica (else primary). |
| `REDIS_URL` | Shared building-block cache across instances (else in-process ETS). |
| `POOL_SIZE`, `INGEST_INTERVAL_MS` | DB pool / relay poll interval. |

> The ingest poller should run on **one** AppView instance (single firehose
> consumer); the timeline API can run on many.

### App (client)
| Env | Effect |
|---|---|
| `ANSIBLE_USE_APPVIEW_FEED=true` + `ANSIBLE_APPVIEW_BASE_URL` | Following feed served by the AppView (fan-out-on-read) instead of the relay global delta — the key fix for relay egress at scale. |

## Connection pooling

Under high concurrency, front PostgreSQL with **PgBouncer** (transaction pooling)
and size `POOL_SIZE` to the bouncer, not the DB max connections. The read replica
gets its own pool (`READ_POOL_SIZE` on the AppView).

## Remaining follow-ups (not yet implemented)

Tracked here so they are not mistaken for done:

1. **Relay `ops` table growth** — append-only and unbounded. Needs time-based
   **partitioning** + a signed-snapshot/retention design before old ops can be
   archived (AppView projections are rebuildable, but rebuild-from-zero needs the
   full op history until snapshots exist). Largest remaining DB-ops item.
2. **Polling → push** — clients poll the delta/timeline on intervals
   (thundering-herd at scale). Replace with a WebSocket firehose subscription
   (`genesis_hosting.md` C-3) + jittered backoff / ETag-304.
3. **ActivityPub / messenger delivery** — outbound HTTP fan-out backed by a
   Postgres retry queue can back up; move to dedicated workers (Oban) with
   backpressure + dead-letter.
4. **Frontend** — serve static assets via CDN; put Cloud Armor in front.
5. **AppView client-side re-verification** — clients currently trust the
   first-party AppView's ingest-time signature check; full re-verification needs
   `feed_items` to also store the original signed payload + signature.
6. **AppView fan-out-on-write + celebrity handling** (Phase C read-model stage 2)
   and **deep-page cache / singleflight** to avoid cache stampede — only needed
   when fan-out-on-read + building-block cache stops keeping up (measure first).
7. **AbuseDetector** is per-instance unless `REDIS_URL` is set (see above).

See `docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md`
for the following-feed scale model and `docs/architecture/genesis_hosting.md` for
the multi-region target.
