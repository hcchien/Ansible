defmodule AnsibleRelay.AbuseDetector do
  @moduledoc """
  Token Bucket based abuse detector for relay ingestion.

  The detector tracks rate limits by subject type (`:did` or `:peer`) and
  returns reason-coded decisions without logging raw DID/IP pairings.

  State lives in a public ETS table owned by this GenServer; `check/2` and
  `suspended?/2` run directly in the caller process (no `GenServer.call`), so
  rate-limit checks for different subjects run fully in parallel rather than
  serializing through one mailbox. Concurrent checks for the *same* subject may
  race slightly (admit a token or two extra at the boundary); that is acceptable
  for a best-effort, time-bound abuse limiter and never blocks distinct subjects.
  """

  use GenServer
  require Logger

  @app :ansible_relay
  @table :ansible_relay_abuse_detector

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
    case Application.get_env(:ansible_relay, :abuse_limiter_adapter) do
      nil ->
        ets_check(type, subject)

      adapter ->
        decision = adapter.check(type, subject, policy(type))
        maybe_log_limit(decision, type, subject)
        decision
    end
  end

  defp ets_check(type, subject) do
    now = now_ms()
    key = {type, subject}
    policy = policy(type)

    decision =
      case :ets.lookup(@table, key) do
        [{^key, _tokens, _updated, until}] when is_integer(until) and until > now ->
          limited(type, until - now)

        found ->
          {tokens, updated_at} =
            case found do
              [{^key, t, u, _until}] -> {t, u}
              [] -> {policy.capacity * 1.0, now}
            end

          available = refill(tokens, updated_at, policy, now)

          if available >= 1.0 do
            :ets.insert(@table, {key, available - 1.0, now, nil})
            :ok
          else
            until = now + policy.suspension_ms
            :ets.insert(@table, {key, 0.0, now, until})
            limited(type, policy.suspension_ms)
          end
      end

    maybe_log_limit(decision, type, subject)
    decision
  end

  @doc "Return whether a subject is currently suspended."
  @spec suspended?(subject_type(), String.t()) :: boolean()
  def suspended?(type, subject) when type in [:did, :peer] and is_binary(subject) do
    now = now_ms()

    case :ets.lookup(@table, {type, subject}) do
      [{_key, _tokens, _updated, until}] when is_integer(until) -> until > now
      _ -> false
    end
  end

  @doc "Clear detector state. Intended for tests and local dev resets."
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  # --- GenServer: owns the ETS table; not on the hot path ---

  # An idle bucket becomes indistinguishable from a fresh one once it has fully
  # refilled and its suspension (if any) has elapsed, so it can be dropped to
  # bound table size. Swept periodically; the timer is the only reason this
  # GenServer holds state beyond owning the table.
  @default_sweep_interval_ms 600_000

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep_idle()
    schedule_sweep()
    {:noreply, state}
  end

  @doc false
  def sweep_now do
    sweep_idle()
  end

  defp schedule_sweep do
    interval = Application.get_env(@app, :abuse_detector_sweep_ms, @default_sweep_interval_ms)
    Process.send_after(self(), :sweep, interval)
  end

  # Remove buckets that are idle: not currently suspended and last touched long
  # enough ago that they would refill to full capacity anyway. Dropping them is
  # observationally equivalent to a fresh bucket.
  defp sweep_idle do
    ensure_table()
    now = now_ms()

    :ets.foldl(
      fn {{type, _subject} = key, tokens, updated_at, until}, acc ->
        policy = policy(type)
        suspended? = is_integer(until) and until > now
        full? = refill(tokens, updated_at, policy, now) >= policy.capacity * 1.0

        if not suspended? and full? do
          :ets.delete(@table, key)
        end

        acc
      end,
      :ok,
      @table
    )

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        @table
    end
  rescue
    ArgumentError -> @table
  end

  # --- Token bucket math ---

  defp refill(tokens, updated_at, policy, now) do
    elapsed_ms = max(now - updated_at, 0)
    refill = elapsed_ms / 1_000 * policy.refill_per_second
    min(policy.capacity * 1.0, tokens + refill)
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
