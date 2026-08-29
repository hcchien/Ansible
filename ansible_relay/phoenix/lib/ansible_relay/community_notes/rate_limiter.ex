defmodule AnsibleRelay.CommunityNotes.RateLimiter do
  @moduledoc "Tier-aware, host-scoped token bucket for Community Note ratings."

  use GenServer
  require Logger

  alias AnsibleRelay.DidAccountCache

  @app :ansible_relay
  @table :ansible_relay_community_notes_rate_limiter
  @default_sweep_interval_ms 600_000
  @default_policies %{
    "basic" => %{capacity: 10, refill_per_second: 10 / 3600, suspension_ms: 600_000},
    "dns_verified" => %{capacity: 20, refill_per_second: 20 / 3600, suspension_ms: 600_000},
    "humanity_limited" => %{capacity: 30, refill_per_second: 30 / 3600, suspension_ms: 600_000},
    "verified_human" => %{capacity: 60, refill_per_second: 60 / 3600, suspension_ms: 600_000},
    "unique_human" => %{capacity: 80, refill_per_second: 80 / 3600, suspension_ms: 600_000}
  }

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def check_rater(did) when is_binary(did) do
    now = System.monotonic_time(:millisecond)
    key = {:rating, did}
    policy = policy(DidAccountCache.reputation_tier(did))

    decision =
      case :ets.lookup(@table, key) do
        [{^key, _tokens, _updated, until}] when is_integer(until) and until > now ->
          limited(until - now)

        found ->
          {tokens, updated_at} =
            case found do
              [{^key, value, updated, _until}] -> {value, updated}
              [] -> {policy.capacity * 1.0, now}
            end

          available =
            min(
              policy.capacity * 1.0,
              tokens + max(now - updated_at, 0) / 1_000 * policy.refill_per_second
            )

          if available >= 1.0 do
            :ets.insert(@table, {key, available - 1.0, now, nil})
            :ok
          else
            until = now + policy.suspension_ms
            :ets.insert(@table, {key, 0.0, now, until})
            limited(policy.suspension_ms)
          end
      end

    if match?({:error, :rate_limited, _}, decision) do
      AnsibleRelay.Metrics.inc("community_notes_rating_rate_limited_total", %{
        tier: tier_name(did)
      })

      Logger.warning(
        "community_notes_rate_limited subject_hash=#{subject_hash(did)} reason=community_notes_rating_rate_limited"
      )
    end

    decision
  end

  defp tier_name(did) do
    tier = DidAccountCache.reputation_tier(did)
    if Map.has_key?(@default_policies, tier), do: tier, else: "basic"
  end

  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    :ets.delete_all_objects(@table)
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(
      self(),
      :sweep,
      Application.get_env(
        @app,
        :community_notes_rate_limiter_sweep_ms,
        @default_sweep_interval_ms
      )
    )
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

      table ->
        table
    end
  rescue
    ArgumentError -> @table
  end

  defp policy(tier) do
    tier = if Map.has_key?(@default_policies, tier), do: tier, else: "basic"
    defaults = Map.fetch!(@default_policies, tier)

    overrides =
      @app
      |> Application.get_env(:community_notes_rating_limits, %{})
      |> Map.get(tier, %{})

    Map.merge(defaults, overrides)
  end

  defp limited(retry_after_ms) do
    {:error, :rate_limited,
     %{
       reason: "community_notes_rating_rate_limited",
       retry_after_ms: retry_after_ms
     }}
  end

  defp subject_hash(subject) do
    :crypto.hash(:sha256, subject)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
