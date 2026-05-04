import Config

config :ansible_relay, AnsibleRelay.Repo,
  username: System.get_env("USER") || "postgres",
  password: "",
  hostname: "localhost",
  database: "ansible_relay_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 5

config :ansible_relay, :port, 4001
