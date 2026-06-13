import Config

config :ansible_appview, ecto_repos: [AnsibleAppview.Repo]

config :ansible_appview, AnsibleAppview.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10

config :ansible_appview, :port, 4000
# Timeline reads use this repo; defaults to the primary. runtime.exs points it at
# AnsibleAppview.ReadRepo when DATABASE_REPLICA_URL is set.
config :ansible_appview, :read_repo, AnsibleAppview.Repo
config :ansible_appview, :start_read_repo, false
# Timeline building-block cache. Default: in-process ETS. runtime.exs switches to
# the Redix adapter when REDIS_URL is set.
config :ansible_appview, :cache_adapter, AnsibleAppview.Cache.ETS
config :ansible_appview, :start_redis, false
# Per-author recent-list cache: entries kept and how many recent items per author.
config :ansible_appview, :author_cache_ttl_ms, 10_000
config :ansible_appview, :author_cache_limit, 100
# Fan-out-on-write home timeline. Default: in-process ETS; Redix when REDIS_URL set.
config :ansible_appview, :home_timeline_adapter, AnsibleAppview.HomeTimeline.ETS
config :ansible_appview, :home_timeline_max, 800
# Authors with more followers than this are treated as celebrities: not fanned
# out on write; merged on read instead.
config :ansible_appview, :celebrity_follower_threshold, 10_000
# Per-item object cache TTL for home-timeline hydration (MGET path).
config :ansible_appview, :item_cache_ttl_ms, 30_000
# How often the ingest poller pulls the relay delta, in milliseconds.
config :ansible_appview, :ingest_interval_ms, 5_000
# Relay base URL the ingest worker polls. Overridden in runtime.exs for prod.
config :ansible_appview, :relay_base_url, "http://localhost:4001"
# Start the background ingest poller with the app. Disabled in tests.
config :ansible_appview, :start_ingest, true

# Inbound federation — curated ActivityPub ingest (design 2026-06-13).
# How often the external poller pulls each enabled curated source's outbox.
# 0 = OFF (never schedule); pull only when explicitly configured.
config :ansible_appview, :external_ingest_interval_ms, 0
# Start the external (inbound-federation) poller with the app. Off by default and
# in tests (tests drive AnsibleAppview.Ingest.ExternalIngest.ingest_source/1).
config :ansible_appview, :start_external_ingest, false
# Curated allowlist seed: a list of maps with :actor_uri, :instance, and
# optionally :display_name / :compliance_level / :enabled. Seeded idempotently.
config :ansible_appview, :external_sources, []

import_config "#{config_env()}.exs"
