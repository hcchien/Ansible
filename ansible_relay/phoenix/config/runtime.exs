import Config

env_int = fn name, default ->
  case System.get_env(name) do
    nil -> default
    value -> String.to_integer(value)
  end
end

env_bool = fn name, default ->
  case System.get_env(name) do
    nil -> default
    value -> String.downcase(value) in ["1", "true", "yes", "on"]
  end
end

split_csv = fn value ->
  value
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
end

if config_env() == :prod do
  config :ansible_relay, :port, env_int.("PORT", 8080)

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Set DATABASE_URL to the production PostgreSQL connection string.
      """

  repo_config = [
    url: database_url,
    pool_size: env_int.("POOL_SIZE", 10)
  ]

  repo_config =
    case System.get_env("DATABASE_SSL") do
      nil -> repo_config
      _ -> Keyword.put(repo_config, :ssl, env_bool.("DATABASE_SSL", false))
    end

  config :ansible_relay, AnsibleRelay.Repo, repo_config

  case System.get_env("WEB_ALLOWED_ORIGINS") do
    nil ->
      :ok

    value ->
      config :ansible_relay, :web_allowed_origins, split_csv.(value)
  end

  case System.get_env("RELAY_ORIGIN") do
    nil -> :ok
    value -> config :ansible_relay, :relay_origin, value
  end

  case System.get_env("FORUM_HOST_BASE_URL") do
    nil -> :ok
    value -> config :ansible_relay, :forum_host_base_url, value
  end
end
