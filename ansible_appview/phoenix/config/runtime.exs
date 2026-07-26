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

  # Optional read replica: route timeline reads to it when configured.
  case System.get_env("DATABASE_REPLICA_URL") do
    nil ->
      :ok

    replica_url ->
      config :ansible_appview, AnsibleAppview.ReadRepo,
        url: replica_url,
        pool_size: String.to_integer(System.get_env("READ_POOL_SIZE") || "10")

      config :ansible_appview, :read_repo, AnsibleAppview.ReadRepo
      config :ansible_appview, :start_read_repo, true
  end

  # Optional Redis cache for multi-instance deployments.
  case System.get_env("REDIS_URL") do
    nil ->
      :ok

    redis_url ->
      config :ansible_appview, :redis_url, redis_url
      config :ansible_appview, :start_redis, true
      config :ansible_appview, :cache_adapter, AnsibleAppview.Cache.Redix
      config :ansible_appview, :home_timeline_adapter, AnsibleAppview.HomeTimeline.Redix
  end

  case System.get_env("INGEST_INTERVAL_MS") do
    nil -> :ok
    value -> config :ansible_appview, :ingest_interval_ms, String.to_integer(value)
  end

  external_interval =
    String.to_integer(System.get_env("EXTERNAL_INGEST_INTERVAL_MS") || "15000")

  config :ansible_appview,
    start_external_ingest: external_interval > 0,
    external_ingest_interval_ms: external_interval
end
