import Config

config :ansible_appview, AnsibleAppview.Repo,
  username: System.get_env("USER") || "postgres",
  password: "",
  hostname: "localhost",
  database: "ansible_appview_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 5

config :ansible_appview, :port, 4003
config :ansible_appview, :relay_base_url, System.get_env("RELAY_BASE_URL") || "http://localhost:4001"
