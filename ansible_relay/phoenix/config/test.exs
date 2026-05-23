import Config

config :ansible_relay, AnsibleRelay.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  database: System.get_env("POSTGRES_DB") || "ansible_relay_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :ansible_relay, :port, 4002
config :ansible_relay, :persist_did_accounts, false
config :ansible_relay, :allow_dev_zkp_proofs, true
