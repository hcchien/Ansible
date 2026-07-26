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
    pool_size: env_int.("POOL_SIZE", 10),
    # Query parameter logs can contain encrypted envelopes and device public
    # keys. Production emits aggregate application metrics instead.
    log: false
  ]

  repo_config =
    case System.get_env("DATABASE_SSL") do
      nil -> repo_config
      _ -> Keyword.put(repo_config, :ssl, env_bool.("DATABASE_SSL", false))
    end

  config :ansible_relay, AnsibleRelay.Repo, repo_config

  # These three drive CORS, the relay's self-advertised origin, and web-thread
  # canonical URLs. Left unset in prod they silently fall back to localhost
  # (relay_discovery_controller.ex, web_session_controller.ex, router.ex), which
  # breaks CORS/audience checks and leaks localhost URLs. Fail closed at boot.
  web_allowed_origins =
    System.get_env("WEB_ALLOWED_ORIGINS") ||
      raise """
      environment variable WEB_ALLOWED_ORIGINS is missing.
      Set WEB_ALLOWED_ORIGINS to a comma-separated list of allowed web origins.
      """

  config :ansible_relay, :web_allowed_origins, split_csv.(web_allowed_origins)

  relay_origin =
    System.get_env("RELAY_ORIGIN") ||
      raise """
      environment variable RELAY_ORIGIN is missing.
      Set RELAY_ORIGIN to this relay's public origin (e.g. https://relay.elix.cool).
      """

  config :ansible_relay, :relay_origin, relay_origin

  activity_pub_delivery_enabled =
    env_bool.("ACTIVITY_PUB_DELIVERY_ENABLED", false)

  config :ansible_relay, :activity_pub_delivery_enabled, activity_pub_delivery_enabled

  activity_pub_blocked_domains =
    System.get_env("ACTIVITY_PUB_BLOCKED_DOMAINS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  config :ansible_relay, :activity_pub_blocked_domains, activity_pub_blocked_domains

  if activity_pub_delivery_enabled do
    activity_pub_public_key_pem =
      System.get_env("ACTIVITY_PUB_PUBLIC_KEY_PEM") ||
        raise """
        ACTIVITY_PUB_PUBLIC_KEY_PEM is required when ActivityPub delivery is enabled.
        """

    activity_pub_private_key_pem =
      System.get_env("ACTIVITY_PUB_PRIVATE_KEY_PEM") ||
        raise """
        ACTIVITY_PUB_PRIVATE_KEY_PEM is required when ActivityPub delivery is enabled.
        """

    config :ansible_relay, :activity_pub_public_key_pem, activity_pub_public_key_pem
    config :ansible_relay, :activity_pub_private_key_pem, activity_pub_private_key_pem
  end

  sync_capability_secret =
    System.get_env("SYNC_CAPABILITY_SECRET") ||
      raise """
      environment variable SYNC_CAPABILITY_SECRET is missing.
      Set it to a high-entropy secret used only for short-lived sync capabilities.
      """

  if byte_size(sync_capability_secret) < 32 do
    raise "SYNC_CAPABILITY_SECRET must contain at least 32 bytes"
  end

  config :ansible_relay, :sync_capability_secret, sync_capability_secret
  config :ansible_relay, :webauthn_rp_id, System.get_env("WEBAUTHN_RP_ID") || "elix.cool"

  config :ansible_relay,
         :webauthn_origin,
         System.get_env("WEBAUTHN_ORIGIN") || "https://elix.cool"

  config :ansible_relay,
         :webauthn_sync_capability_required,
         env_bool.("WEBAUTHN_SYNC_CAPABILITY_REQUIRED", false)

  # Remains off in production until the private-board protocol has completed
  # its independent cryptographic review. Dev/test can opt in explicitly.
  config :ansible_relay,
         :encrypted_boards_enabled,
         env_bool.("ENCRYPTED_BOARDS_ENABLED", false)

  forum_host_base_url =
    System.get_env("FORUM_HOST_BASE_URL") ||
      raise """
      environment variable FORUM_HOST_BASE_URL is missing.
      Set FORUM_HOST_BASE_URL to the public base URL for hosted forum content.
      """

  config :ansible_relay, :forum_host_base_url, forum_host_base_url

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

  normalized_issuer_key = String.downcase(issuer_public_key_hex)

  # Reject known dev/placeholder sentinels: an all-zeros or all-ones key passes
  # the hex format check but is never a real trust anchor. Also decode-validate
  # it as a 32-byte Ed25519 public key (OTP has no cheap curve-point check
  # without a NIF; rejecting the sentinels + confirming a 32-byte decode is the
  # least we can do to stop a release trusting a dev key).
  all_zeros = String.duplicate("0", 64)
  all_ones = String.duplicate("f", 64)

  if normalized_issuer_key in [all_zeros, all_ones] do
    raise """
    environment variable ISSUER_PUBLIC_KEY_HEX is a known dev/placeholder sentinel
    (all-zeros or all-ones). Set it to the real production VC issuer public key.
    """
  end

  case Base.decode16(normalized_issuer_key, case: :lower) do
    {:ok, raw} when byte_size(raw) == 32 ->
      :ok

    _ ->
      raise """
      environment variable ISSUER_PUBLIC_KEY_HEX must decode to a 32-byte Ed25519 public key.
      """
  end

  config :ansible_relay, :trusted_vc_issuers, [
    %{did: issuer_did, public_key_hex: String.downcase(issuer_public_key_hex)}
  ]

  # Phase 2.3 — op snapshot signing key (32-byte Ed25519 seed, 64 hex chars).
  # Required in prod: if unset the relay would derive a per-node dev key (see
  # SnapshotSigner.derived_dev_keypair/0) that is neither stable nor operator-
  # controlled, so published snapshots could not be verified across nodes or a
  # redeploy. Raise at boot rather than warn.
  snapshot_signing_key_hex =
    System.get_env("ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX") ||
      raise """
      environment variable ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX is missing.
      Set it to a 32-byte Ed25519 snapshot signing seed in hex (64 chars) so
      snapshots are signed by a stable, operator-controlled key.
      """

  unless Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, snapshot_signing_key_hex) do
    raise """
    environment variable ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX must be a
    64-character Ed25519 seed in hex (32 bytes).
    """
  end

  config :ansible_relay, :snapshot_signing_key_hex, String.downcase(snapshot_signing_key_hex)

  # Finding 4 — dev-signature bypass must never be reachable in prod. These
  # flags are false in config.exs and true in dev.exs; a config regression that
  # left either true would let "dev-signature-"/dev identity signatures through.
  # Fail loudly at boot rather than run with the bypass latent.
  if Application.get_env(:ansible_relay, :allow_dev_publication_signatures, false) do
    raise "allow_dev_publication_signatures must be false in production"
  end

  if Application.get_env(:ansible_relay, :allow_dev_identity_signatures, false) do
    raise "allow_dev_identity_signatures must be false in production"
  end

  if Application.get_env(:ansible_relay, :allow_dev_zkp_proofs, false) do
    raise "allow_dev_zkp_proofs must be false in production"
  end

  # P0 — the dev ZKP verification-key placeholders in config.exs
  # ("sha256:dev-vk-hash-placeholder", "sha256:dev-passport-v1-placeholder")
  # must never be active trust anchors in a production release. The Phase 1 ZKP
  # challenge/anchor flow is retired (no code consumes :zkp_verification_keys
  # today), so prod boots with NO active keys — overriding config.exs — unless
  # the operator explicitly supplies audited entries via
  # ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS (JSON array of
  # {"version","hash":"sha256:<64 hex>","status":"active"|"retired"}).
  # Placeholder or malformed entries raise at boot (fail closed); see
  # AnsibleRelay.Config.ZkpVerificationKeys.
  config :ansible_relay,
         :zkp_verification_keys,
         AnsibleRelay.Config.ZkpVerificationKeys.load_prod!(
           System.get_env("ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS")
         )

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
