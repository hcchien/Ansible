import Config

if config_env() == :prod do
  config :ansible_appview, :port, String.to_integer(System.get_env("PORT") || "8080")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Set DATABASE_URL to the AppView PostgreSQL connection string.
      """

  config :ansible_appview, AnsibleAppview.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  relay_base_url =
    System.get_env("RELAY_BASE_URL") ||
      raise """
      environment variable RELAY_BASE_URL is missing.
      Set RELAY_BASE_URL to the relay base URL the AppView ingests from.
      """

  config :ansible_appview, :relay_base_url, relay_base_url

  case System.get_env("INGEST_INTERVAL_MS") do
    nil -> :ok
    value -> config :ansible_appview, :ingest_interval_ms, String.to_integer(value)
  end
end
