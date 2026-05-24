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

  issuer_did =
    System.get_env("ISSUER_DID") ||
      raise """
      environment variable ISSUER_DID is missing.
      Set ISSUER_DID to the trusted production VC issuer DID.
      """

  issuer_public_key_hex =
    System.get_env("ISSUER_PUBLIC_KEY_HEX") ||
      raise """
      environment variable ISSUER_PUBLIC_KEY_HEX is missing.
      Set ISSUER_PUBLIC_KEY_HEX to the trusted production VC issuer Ed25519 public key.
      """

  unless Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, issuer_public_key_hex) do
    raise """
    environment variable ISSUER_PUBLIC_KEY_HEX must be a 64-character Ed25519 hex public key.
    """
  end

  config :ansible_relay, :trusted_vc_issuers, [
    %{did: issuer_did, public_key_hex: String.downcase(issuer_public_key_hex)}
  ]
end
