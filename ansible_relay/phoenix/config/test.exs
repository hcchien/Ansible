import Config

config :ansible_relay, AnsibleRelay.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ansible_relay_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :ansible_relay, :port, 4002
config :ansible_relay, :persist_did_accounts, false
