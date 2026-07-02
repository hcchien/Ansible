defmodule AnsibleRelay.IdentityCache do
  @moduledoc """
  ETS-backed cache of verified DID identities.

  V1.1 Comp C — stores DID → {public_key_hex, nullifier, verified_at, expires_at}
  after Phase 1 anchoring. Phase 2 ops lookup this cache for sig verification.

  Three ETS tables:
    :verified_did_cache  — DID → entry map (read_concurrency: true, Phase 2 is read-heavy)
    :nullifier_index     — nullifier → DID (dedup check during Phase 1)
    :identity_challenges — DID → challenge entry map (replay protection during Phase 1)
  """

  use GenServer
  import Ecto.Query
  require Logger

  alias AnsibleRelay.{Repo, Db.VerifiedDid}

  @table :verified_did_cache
  @nullifier_table :nullifier_index
  @challenge_table :identity_challenges

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Store a verified DID identity, indexed by nullifier for dedup."
  def put(did, public_key_hex, nullifier \\ nil, expires_at \\ nil) do
    ttl_seconds = Application.get_env(:ansible_relay, :did_cache_ttl_seconds, 7_776_000)
    expiry = expires_at || DateTime.add(DateTime.utc_now(), ttl_seconds, :second)

    entry = %{
      public_key_hex: public_key_hex,
      nullifier: nullifier,
      verified_at: DateTime.utc_now(),
      expires_at: expiry
    }

    :ets.insert(@table, {did, entry})

    if nullifier do
      :ets.insert(@nullifier_table, {nullifier, did})
    end

    # Write-through to PostgreSQL for durability
    Repo.insert(
      %VerifiedDid{
        did: did,
        public_key_hex: public_key_hex,
        nullifier: nullifier || "",
        verified_at: DateTime.utc_now(),
        expires_at: expiry
      },
      on_conflict: {:replace, [:public_key_hex, :expires_at]},
      conflict_target: :did
    )

    :ok
  end

  @doc """
  Look up a DID. Returns `{:ok, entry}`, `:not_found`, or `{:error, :unavailable}`.

  On an ETS miss, reads through to PostgreSQL and repopulates the local cache, so
  any relay instance can serve a DID anchored on another instance (shared-DB
  horizontal scaling).

  A genuine "no such DID" is `:not_found`. A DB/infrastructure outage is
  `{:error, :unavailable}` — distinct so callers on the ingest path can return a
  retryable 503 instead of a 401 that would prompt a client to (destructively)
  re-anchor during a transient Postgres blip.
  """
  def get(did) do
    case :ets.lookup(@table, did) do
      [{^did, entry}] -> {:ok, entry}
      [] -> read_through(did)
    end
  end

  defp read_through(did) do
    case Repo.get_by(VerifiedDid, did: did) do
      nil ->
        :not_found

      %VerifiedDid{} = row ->
        if DateTime.compare(DateTime.utc_now(), row.expires_at) == :lt do
          entry = %{
            public_key_hex: row.public_key_hex,
            nullifier: blank_to_nil(row.nullifier),
            verified_at: row.verified_at,
            expires_at: row.expires_at
          }

          :ets.insert(@table, {did, entry})

          if entry.nullifier do
            :ets.insert(@nullifier_table, {entry.nullifier, did})
          end

          {:ok, entry}
        else
          :not_found
        end
    end
  rescue
    # A DB error is an outage, not a missing row — surface it as :unavailable so
    # the ingest path can 503 rather than falsely 401 "unverified_did".
    _ -> {:error, :unavailable}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc """
  Returns true if the DID is verified and not expired.

  Boolean by contract for its many callers (auth plugs, signed intents): both a
  true miss and a DB outage return `false`, unchanged from before. Callers that
  must distinguish an outage (the op ingest path) use `get/1` directly and check
  for `{:error, :unavailable}`.
  """
  def verified?(did) do
    case get(did) do
      {:ok, %{expires_at: expires_at}} ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :lt

      _ ->
        false
    end
  end

  @doc """
  Check if a nullifier has already been registered. On an ETS miss, reads through
  to PostgreSQL so duplicate-prevention holds across instances (and under the
  lazy cache, where the nullifier index is not preloaded).
  """
  def nullifier_exists?(nullifier) do
    case :ets.lookup(@nullifier_table, nullifier) do
      [] ->
        Repo.exists?(
          from(v in VerifiedDid, where: v.nullifier == ^nullifier and v.nullifier != "")
        )

      _ ->
        true
    end
  end

  @doc "Remove a DID (revocation). Also removes its nullifier index entry."
  def remove(did) do
    case get(did) do
      {:ok, %{nullifier: nullifier}} when not is_nil(nullifier) ->
        :ets.delete(@nullifier_table, nullifier)

      _ ->
        :ok
    end

    :ets.delete(@table, did)
    # Also remove the durable row so read-through cannot resurrect a revoked DID
    # on this or any other instance.
    Repo.delete_all(from(v in VerifiedDid, where: v.did == ^did))
    :ok
  end

  @doc "Return the public key hex for a verified DID, or nil."
  def public_key_hex(did) do
    case get(did) do
      {:ok, %{public_key_hex: pkh}} -> pkh
      _ -> nil
    end
  end

  @doc "Issue a short-lived Phase 1 challenge nonce for a DID."
  def issue_challenge(did, expires_at \\ nil) when is_binary(did) do
    ttl_seconds = Application.get_env(:ansible_relay, :identity_challenge_ttl_seconds, 600)
    now = DateTime.utc_now()
    expiry = expires_at || DateTime.add(now, ttl_seconds, :second)

    entry = %{
      challenge: random_challenge(),
      issued_at: now,
      expires_at: expiry
    }

    :ets.insert(@challenge_table, {did, entry})
    {:ok, entry}
  end

  @doc "Consume a Phase 1 challenge exactly once."
  def consume_challenge(did, challenge) when is_binary(did) and is_binary(challenge) do
    case :ets.lookup(@challenge_table, did) do
      [{^did, %{challenge: ^challenge, expires_at: expires_at}}] ->
        :ets.delete(@challenge_table, did)

        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          :ok
        else
          {:error, :expired_challenge}
        end

      [{^did, _entry}] ->
        {:error, :invalid_challenge}

      [] ->
        {:error, :invalid_challenge}
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@nullifier_table, [:set, :public, :named_table])
    :ets.new(@challenge_table, [:set, :public, :named_table])

    # Lazy by default: rely on per-DID read-through instead of loading every
    # verified DID into RAM at boot (which grows per-instance memory and startup
    # time with the total DID count). Eager restore is opt-in.
    restored =
      if Application.get_env(:ansible_relay, :eager_identity_cache, false) do
        restore_persisted_identities()
      else
        0
      end

    Logger.info("IdentityCache ready (eager_restored=#{restored})")
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep_expired()
    sweep_expired_challenges()
    schedule_sweep()
    {:noreply, state}
  end

  @doc false
  def sweep_now do
    {sweep_expired(), sweep_expired_challenges()}
  end

  defp schedule_sweep do
    interval = Application.get_env(:ansible_relay, :identity_cache_sweep_ms, 3_600_000)
    Process.send_after(self(), :sweep, interval)
  end

  # Evicts expired entries so the lazy cache stays bounded by the active DID set
  # rather than every DID ever looked up.
  defp sweep_expired do
    now = DateTime.utc_now()

    expired =
      :ets.foldl(
        fn {did, entry}, acc ->
          if DateTime.compare(entry.expires_at, now) != :gt do
            if entry[:nullifier], do: :ets.delete(@nullifier_table, entry.nullifier)
            [did | acc]
          else
            acc
          end
        end,
        [],
        @table
      )

    Enum.each(expired, &:ets.delete(@table, &1))
    length(expired)
  end

  # Phase 1 challenges are consumed exactly once, but an issued-then-abandoned
  # challenge otherwise lingers in the table forever. Sweep expired ones so the
  # replay-protection table stays bounded by in-flight anchoring flows.
  defp sweep_expired_challenges do
    now = DateTime.utc_now()

    expired =
      :ets.foldl(
        fn {did, entry}, acc ->
          if DateTime.compare(entry.expires_at, now) != :gt do
            [did | acc]
          else
            acc
          end
        end,
        [],
        @challenge_table
      )

    Enum.each(expired, &:ets.delete(@challenge_table, &1))
    length(expired)
  end

  defp restore_persisted_identities do
    now = DateTime.utc_now()

    VerifiedDid
    |> where([identity], identity.expires_at > ^now)
    |> Repo.all()
    |> Enum.reduce(0, fn identity, count ->
      entry = %{
        public_key_hex: identity.public_key_hex,
        nullifier: empty_to_nil(identity.nullifier),
        verified_at: identity.verified_at,
        expires_at: identity.expires_at
      }

      :ets.insert(@table, {identity.did, entry})

      if entry.nullifier do
        :ets.insert(@nullifier_table, {entry.nullifier, identity.did})
      end

      count + 1
    end)
  rescue
    error ->
      Logger.warning("IdentityCache restore skipped: #{Exception.message(error)}")
      0
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp random_challenge do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
