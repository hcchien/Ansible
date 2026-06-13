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

  # Phase 2.3 — op snapshot signing key (32-byte Ed25519 seed, 64 hex chars).
  # If unset, the relay derives a per-node dev key and logs a warning; set this
  # in production so snapshots are signed by a stable, operator-controlled key.
  case System.get_env("ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX") do
    nil ->
      :ok

    hex ->
      unless Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, hex) do
        raise """
        environment variable ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX must be a
        64-character Ed25519 seed in hex (32 bytes).
        """
      end

      config :ansible_relay, :snapshot_signing_key_hex, String.downcase(hex)
  end

  # Phase 2.3 — op retention window in days. Unset = :infinity (never prune).
  case System.get_env("ANSIBLE_RELAY_SNAPSHOT_RETENTION_DAYS") do
    nil -> :ok
    value -> config :ansible_relay, :snapshot_retention_days, String.to_integer(value)
  end

  # Shared cross-instance abuse limiter (Redis). Without it, rate limits are
  # per-instance (looser behind a load balancer).
  case System.get_env("REDIS_URL") do
    nil ->
      :ok

    redis_url ->
      config :ansible_relay, :abuse_limiter_redis_url, redis_url
      config :ansible_relay, :abuse_limiter_adapter, AnsibleRelay.AbuseDetector.Redis
  end

  # Multi-node Erlang clustering (e.g. GKE). Set LIBCLUSTER_HOSTS to a
  # comma-separated list of full node names to connect via epmd. Unset = single
  # node (Cloud Run scales statelessly over shared PostgreSQL).
  case System.get_env("LIBCLUSTER_HOSTS") do
    nil ->
      :ok

    hosts ->
      nodes =
        hosts
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.to_atom()))

      config :libcluster,
        topologies: [
          relay: [
            strategy: Cluster.Strategy.Epmd,
            config: [hosts: nodes]
          ]
        ]
  end
end
