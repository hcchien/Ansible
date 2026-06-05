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
# How often the ingest poller pulls the relay delta, in milliseconds.
config :ansible_appview, :ingest_interval_ms, 5_000
# Relay base URL the ingest worker polls. Overridden in runtime.exs for prod.
config :ansible_appview, :relay_base_url, "http://localhost:4001"
# Start the background ingest poller with the app. Disabled in tests.
config :ansible_appview, :start_ingest, true

import_config "#{config_env()}.exs"
