import Config

config :ansible_appview, AnsibleAppview.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  database: System.get_env("POSTGRES_DB") || "ansible_appview_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :ansible_appview, :port, String.to_integer(System.get_env("APPVIEW_TEST_PORT") || "4004")
# Tests drive the folder/poller directly; do not auto-start the background loop.
config :ansible_appview, :start_ingest, false
