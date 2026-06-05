defmodule AnsibleRelay.AbuseDetector.Redis do
  @moduledoc """
  Shared cross-instance abuse limiter backed by Redis (fixed-window INCR), so
  rate limits are accurate when multiple relay instances sit behind a load
  balancer (the in-process ETS limiter only counts per instance). Enabled when
  `REDIS_URL` is set; the connection is named `:relay_redis`. Fails open (a Redis
  outage degrades to no limiting rather than blocking traffic).
  """

  @conn :relay_redis

  @spec check(:did | :peer, String.t(), map()) ::
          :ok | {:error, :rate_limited, map()}
  def check(type, subject, policy) do
    window_ms = max(div(policy.capacity * 1000, max(policy.refill_per_second, 1)), 1_000)
    key = "rl:#{type}:#{subject}"

    case Redix.command(@conn, ["INCR", key]) do
      {:ok, 1} ->
        _ = Redix.command(@conn, ["PEXPIRE", key, Integer.to_string(window_ms)])
        :ok

      {:ok, count} when is_integer(count) and count > 0 ->
        if count > policy.capacity do
          {:error, :rate_limited,
           %{
             subject_type: Atom.to_string(type),
             reason: "#{type}_rate_limited",
             retry_after_ms: window_ms
           }}
        else
          :ok
        end

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end
end
