defmodule AnsibleRelay.DidAccountCache do
  @moduledoc """
  ETS-backed cache for V2.0 Passkeys/did:plc accounts.

  Three ETS tables:
    :did_account_cache   — DID → entry map (read_concurrency: true)
    :handle_index        — handle → DID (for handle-based lookups)
    :registration_nonces — public_key_hex → {nonce, expires_at} (TTL: 5 minutes)
    :pending_handles     — handle → public_key_hex while registration is pending
    :nostr_binding_cache — Nostr pubkey → short-lived holder DID trust binding
  """

  use GenServer
  require Logger

  alias AnsibleRelay.{Repo, Db.DidAccount}

  @table :did_account_cache
  @handle_table :handle_index
  @nonce_table :registration_nonces
  @pending_handle_table :pending_handles
  @nostr_binding_table :nostr_binding_cache
  @nonce_ttl_seconds 300

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Store a DID account entry, indexed by handle. Write-through to PostgreSQL."
  def put(did, public_key_hex, handle, opts \\ []) do
    ttl_seconds =
      Keyword.get(
        opts,
        :ttl_seconds,
        Application.get_env(:ansible_relay, :did_account_cache_ttl_seconds, 7_776_000)
      )

    now = DateTime.utc_now()
    expiry = Keyword.get(opts, :expires_at) || DateTime.add(now, ttl_seconds, :second)
    pds_endpoint = Keyword.get(opts, :pds_endpoint, "https://trisaura.io")
    reputation_tier = Keyword.get(opts, :reputation_tier, "basic")

    entry = %{
      public_key_hex: public_key_hex,
      handle: handle,
      pds_endpoint: pds_endpoint,
      reputation_tier: reputation_tier,
      registered_at: now,
      expires_at: expiry
    }

    :ets.insert(@table, {did, entry})
    :ets.insert(@handle_table, {handle, did})

    if Application.get_env(:ansible_relay, :persist_did_accounts, true) do
      Repo.insert(
        %DidAccount{
          did: did,
          public_key_hex: public_key_hex,
          handle: handle,
          pds_endpoint: pds_endpoint,
          reputation_tier: reputation_tier,
          registered_at: now,
          expires_at: expiry
        },
        on_conflict:
          {:replace, [:public_key_hex, :handle, :pds_endpoint, :reputation_tier, :expires_at]},
        conflict_target: :did
      )
    end

    :ok
  end

  @doc "Look up a DID. Returns {:ok, entry} or :not_found."
  def get(did) do
    case :ets.lookup(@table, did) do
      [{^did, entry}] -> {:ok, entry}
      [] -> :not_found
    end
  end

  @doc "Returns true if the DID is registered and not expired."
  def active?(did) do
    case get(did) do
      {:ok, %{expires_at: expires_at}} ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :lt

      :not_found ->
        false
    end
  end

  @doc "Look up a DID by handle. Returns {:ok, did} or :not_found."
  def get_by_handle(handle) do
    case :ets.lookup(@handle_table, handle) do
      [{^handle, did}] -> {:ok, did}
      [] -> :not_found
    end
  end

  @doc "Return the public key hex for a DID, or nil."
  def public_key_hex(did) do
    case get(did) do
      {:ok, %{public_key_hex: pkh}} -> pkh
      _ -> nil
    end
  end

  @doc "Return the reputation tier for a DID, defaulting to \"basic\"."
  def reputation_tier(did) do
    case get(did) do
      {:ok, %{reputation_tier: tier}} when is_binary(tier) -> tier
      _ -> "basic"
    end
  end

  @doc "Clear all in-memory DID account state. Intended for tests."
  def reset do
    :ets.delete_all_objects(@table)
    :ets.delete_all_objects(@handle_table)
    :ets.delete_all_objects(@nonce_table)
    :ets.delete_all_objects(@pending_handle_table)
    :ets.delete_all_objects(@nostr_binding_table)
    :ok
  end

  @doc "Store a short-lived relay-local Nostr pubkey trust binding."
  def put_nostr_binding(nostr_pubkey, holder_did, reputation_tier, opts \\ [])
      when is_binary(nostr_pubkey) and is_binary(holder_did) and is_binary(reputation_tier) do
    ttl_seconds =
      Keyword.get(
        opts,
        :ttl_seconds,
        Application.get_env(:ansible_relay, :nostr_binding_ttl_seconds, 300)
      )

    now = DateTime.utc_now()
    expires_at = Keyword.get(opts, :expires_at) || DateTime.add(now, ttl_seconds, :second)

    :ets.insert(
      @nostr_binding_table,
      {String.downcase(nostr_pubkey),
       %{
         holder_did: holder_did,
         reputation_tier: reputation_tier,
         bound_at: now,
         expires_at: expires_at
       }}
    )

    :ok
  end

  @doc "Look up an active relay-local Nostr pubkey trust binding."
  def get_nostr_binding(nostr_pubkey) when is_binary(nostr_pubkey) do
    key = String.downcase(nostr_pubkey)

    case :ets.lookup(@nostr_binding_table, key) do
      [{^key, %{expires_at: expires_at} = entry}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, entry}
        else
          :ets.delete(@nostr_binding_table, key)
          :not_found
        end

      [] ->
        :not_found
    end
  end

  def get_nostr_binding(_nostr_pubkey), do: :not_found

  @doc "Issue a registration nonce for a public key (TTL: 5 minutes)."
  def issue_nonce(public_key_hex, handle) when is_binary(public_key_hex) and is_binary(handle) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, @nonce_ttl_seconds, :second)
    nonce = random_nonce()

    with :ok <- ensure_handle_not_pending(handle, now) do
      :ets.insert(
        @nonce_table,
        {public_key_hex, %{nonce: nonce, expires_at: expires_at, handle: handle}}
      )

      :ets.insert(
        @pending_handle_table,
        {handle, %{public_key_hex: public_key_hex, expires_at: expires_at}}
      )

      {:ok, %{nonce: nonce, expires_at: expires_at, handle: handle}}
    end
  end

  @doc "Consume a registration nonce exactly once. Returns :ok or {:error, reason}."
  def consume_nonce(public_key_hex, nonce, handle)
      when is_binary(public_key_hex) and is_binary(nonce) and is_binary(handle) do
    case :ets.lookup(@nonce_table, public_key_hex) do
      [{^public_key_hex, %{nonce: ^nonce, expires_at: expires_at, handle: ^handle}}] ->
        :ets.delete(@nonce_table, public_key_hex)
        :ets.delete(@pending_handle_table, handle)

        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          :ok
        else
          {:error, :expired_nonce}
        end

      [{^public_key_hex, %{nonce: ^nonce}}] ->
        {:error, :handle_mismatch}

      [{^public_key_hex, _entry}] ->
        {:error, :invalid_nonce}

      [] ->
        {:error, :invalid_nonce}
    end
  end

  def consume_nonce(public_key_hex, nonce) do
    case :ets.lookup(@nonce_table, public_key_hex) do
      [{^public_key_hex, %{handle: handle}}] -> consume_nonce(public_key_hex, nonce, handle)
      _ -> {:error, :invalid_nonce}
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@handle_table, [:set, :public, :named_table])
    :ets.new(@nonce_table, [:set, :public, :named_table])
    :ets.new(@pending_handle_table, [:set, :public, :named_table])
    :ets.new(@nostr_binding_table, [:set, :public, :named_table, read_concurrency: true])
    Logger.info("DidAccountCache ETS tables created")
    {:ok, %{}}
  end

  defp ensure_handle_not_pending(handle, now) do
    case :ets.lookup(@pending_handle_table, handle) do
      [{^handle, %{expires_at: expires_at}}] ->
        if DateTime.compare(now, expires_at) == :lt do
          {:error, :handle_pending}
        else
          :ets.delete(@pending_handle_table, handle)
          :ok
        end

      [] ->
        :ok
    end
  end

  defp random_nonce do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
