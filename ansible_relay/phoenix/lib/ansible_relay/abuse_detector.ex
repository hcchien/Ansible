defmodule AnsibleRelay.AbuseDetector do
  @moduledoc """
  Token Bucket based abuse detector for relay ingestion.

  The detector tracks rate limits by subject type (`:did` or `:peer`) and
  returns reason-coded decisions without logging raw DID/IP pairings.
  """

  use GenServer
  require Logger

  @app :ansible_relay

  @type subject_type :: :did | :peer
  @type decision :: :ok | {:error, :rate_limited, map()}

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check and consume one DID-level Op token."
  @spec check_did(String.t()) :: decision()
  def check_did(did), do: check(:did, did)

  @doc "Check and consume one peer-level invalid-message token."
  @spec check_peer(String.t()) :: decision()
  def check_peer(peer_id), do: check(:peer, peer_id)

  @doc "Check and consume one token for a subject."
  @spec check(subject_type(), String.t()) :: decision()
  def check(type, subject) when type in [:did, :peer] and is_binary(subject) do
    GenServer.call(__MODULE__, {:check, type, subject})
  end

  @doc "Return whether a subject is currently suspended."
  @spec suspended?(subject_type(), String.t()) :: boolean()
  def suspended?(type, subject) when type in [:did, :peer] and is_binary(subject) do
    GenServer.call(__MODULE__, {:suspended?, type, subject})
  end

  @doc "Clear detector state. Intended for tests and local dev resets."
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{buckets: %{}, suspended_until: %{}}}
  end

  @impl true
  def handle_call({:check, type, subject}, _from, state) do
    now = now_ms()
    key = {type, subject}
    policy = policy(type)

    case Map.get(state.suspended_until, key) do
      until_ms when is_integer(until_ms) and until_ms > now ->
        {:reply, limited(type, until_ms - now), state}

      _ ->
        state = %{state | suspended_until: Map.delete(state.suspended_until, key)}
        {decision, state} = consume_token(state, key, policy, now)
        maybe_log_limit(decision, type, subject)
        {:reply, decision, state}
    end
  end

  @impl true
  def handle_call({:suspended?, type, subject}, _from, state) do
    now = now_ms()

    suspended =
      case Map.get(state.suspended_until, {type, subject}) do
        until_ms when is_integer(until_ms) -> until_ms > now
        _ -> false
      end

    {:reply, suspended, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{buckets: %{}, suspended_until: %{}}}
  end

  defp consume_token(state, key, policy, now) do
    bucket = Map.get(state.buckets, key, %{tokens: policy.capacity, updated_at: now})
    tokens = refill(bucket, policy, now)

    if tokens >= 1.0 do
      buckets = Map.put(state.buckets, key, %{tokens: tokens - 1.0, updated_at: now})
      {:ok, %{state | buckets: buckets}}
    else
      until_ms = now + policy.suspension_ms

      state = %{
        state
        | suspended_until: Map.put(state.suspended_until, key, until_ms),
          buckets: Map.put(state.buckets, key, %{tokens: 0.0, updated_at: now})
      }

      {limited(elem(key, 0), policy.suspension_ms), state}
    end
  end

  defp refill(bucket, policy, now) do
    elapsed_ms = max(now - bucket.updated_at, 0)
    refill = elapsed_ms / 1_000 * policy.refill_per_second
    min(policy.capacity * 1.0, bucket.tokens + refill)
  end

  defp policy(type) do
    cfg = Application.get_env(@app, :abuse_detector, %{})
    type_cfg = Map.get(cfg, type, %{})

    %{
      capacity: Map.get(type_cfg, :capacity, default_capacity(type)),
      refill_per_second: Map.get(type_cfg, :refill_per_second, default_capacity(type)),
      suspension_ms: Map.get(type_cfg, :suspension_ms, 60_000)
    }
  end

  defp default_capacity(:did), do: 5
  defp default_capacity(:peer), do: 20

  defp limited(:did, retry_after_ms) do
    {:error, :rate_limited,
     %{
       subject_type: "did",
       reason: "did_rate_limited",
       retry_after_ms: retry_after_ms
     }}
  end

  defp limited(:peer, retry_after_ms) do
    {:error, :rate_limited,
     %{
       subject_type: "peer",
       reason: "peer_rate_limited",
       retry_after_ms: retry_after_ms
     }}
  end

  defp maybe_log_limit({:error, :rate_limited, detail}, type, subject) do
    Logger.warning(
      "abuse_detector rate_limited subject_type=#{type} subject_hash=#{subject_hash(subject)} reason=#{detail.reason}"
    )
  end

  defp maybe_log_limit(:ok, _type, _subject), do: :ok

  defp subject_hash(subject) do
    :crypto.hash(:sha256, subject)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp now_ms do
    System.monotonic_time(:millisecond)
  end
end
