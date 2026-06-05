import Config

config :ansible_appview, ecto_repos: [AnsibleAppview.Repo]

config :ansible_appview, AnsibleAppview.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10

config :ansible_appview, :port, 4000
# How often the ingest poller pulls the relay delta, in milliseconds.
config :ansible_appview, :ingest_interval_ms, 5_000
# Relay base URL the ingest worker polls. Overridden in runtime.exs for prod.
config :ansible_appview, :relay_base_url, "http://localhost:4001"
# Start the background ingest poller with the app. Disabled in tests.
config :ansible_appview, :start_ingest, true

import_config "#{config_env()}.exs"
