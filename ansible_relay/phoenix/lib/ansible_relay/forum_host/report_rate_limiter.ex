defmodule AnsibleRelay.ForumHost.ReportRateLimiter do
  @moduledoc """
  Tier-aware token bucket for content-report submissions.

  Reporting is itself an abuse vector (constitution Base Rule 4), so reports
  are rate-limited per reporter DID with stricter limits for lower
  `AnsibleRelay.ReputationTier` ranks. Mirrors the ETS token-bucket pattern of
  `AnsibleRelay.AbuseDetector` but is deliberately a separate, host-level
  limiter — the abuse detector is system-level enforcement and stays separate
  (constitution Rule 7).

  Policies can be overridden per tier via the `:forum_host_report_limits`
  application env, e.g.
  `%{"basic" => %{capacity: 1, refill_per_second: 0, suspension_ms: 60_000}}`.
  """

  use GenServer
  require Logger

  alias AnsibleRelay.DidAccountCache

  @app :ansible_relay
  @table :ansible_relay_forum_host_report_limiter

  # Lower tiers get fewer reports per window (Base Rule 4: stricter limits
  # for lower-trust subjects). Refill is roughly the capacity per hour.
  @default_policies %{
    "basic" => %{capacity: 3, refill_per_second: 3 / 3600, suspension_ms: 600_000},
    "dns_verified" => %{capacity: 6, refill_per_second: 6 / 3600, suspension_ms: 600_000},
    "verified_human" => %{capacity: 12, refill_per_second: 12 / 3600, suspension_ms: 600_000}
  }

  @type decision :: :ok | {:error, :rate_limited, map()}

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check and consume one report token for the reporter DID."
  @spec check_reporter(String.t()) :: decision()
  def check_reporter(did) when is_binary(did) do
    now = now_ms()
    key = {:report, did}
    policy = policy(DidAccountCache.reputation_tier(did))

    decision =
      case :ets.lookup(@table, key) do
        [{^key, _tokens, _updated, until}] when is_integer(until) and until > now ->
          limited(until - now)

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
            limited(policy.suspension_ms)
          end
      end

    maybe_log_limit(decision, did)
    decision
  end

  @doc "Clear limiter state. Intended for tests and local dev resets."
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  # --- GenServer: owns the ETS table; not on the hot path ---

  # Idle buckets (fully refilled, not suspended) are dropped periodically so the
  # table stays bounded by active reporters rather than every DID that ever
  # reported. See AnsibleRelay.AbuseDetector for the same pattern.
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
  def sweep_now, do: sweep_idle()

  defp schedule_sweep do
    interval =
      Application.get_env(@app, :forum_host_report_limiter_sweep_ms, @default_sweep_interval_ms)

    Process.send_after(self(), :sweep, interval)
  end

  defp sweep_idle do
    ensure_table()
    now = now_ms()

    :ets.foldl(
      fn {{:report, did} = key, tokens, updated_at, until}, acc ->
        policy = policy(DidAccountCache.reputation_tier(did))
        suspended? = is_integer(until) and until > now
        full? = refill(tokens, updated_at, policy, now) >= policy.capacity * 1.0

        if not suspended? and full?, do: :ets.delete(@table, key)
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

  # Unknown tiers fall back to the strictest (basic) policy so a downgrade or
  # garbage tier never loosens the limit.
  defp policy(tier) do
    tier = if Map.has_key?(@default_policies, tier), do: tier, else: "basic"
    defaults = Map.fetch!(@default_policies, tier)
    overrides = @app |> Application.get_env(:forum_host_report_limits, %{}) |> Map.get(tier, %{})
    Map.merge(defaults, overrides)
  end

  defp limited(retry_after_ms) do
    {:error, :rate_limited,
     %{
       subject_type: "did",
       reason: "report_rate_limited",
       retry_after_ms: retry_after_ms
     }}
  end

  defp maybe_log_limit({:error, :rate_limited, detail}, did) do
    Logger.warning(
      "report_rate_limiter rate_limited subject_hash=#{subject_hash(did)} reason=#{detail.reason}"
    )
  end

  defp maybe_log_limit(:ok, _did), do: :ok

  defp subject_hash(subject) do
    :crypto.hash(:sha256, subject)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp now_ms do
    System.monotonic_time(:millisecond)
  end
end
