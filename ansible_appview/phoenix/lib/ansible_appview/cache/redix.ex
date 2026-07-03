defmodule AnsibleAppview.Cache.Redix do
  @moduledoc """
  Redis cache adapter (multi-instance). Values are Erlang-term encoded. Enabled
  when `REDIS_URL` is configured; the Redix connection is named `:appview_redis`
  and started in the supervision tree. Fails open (treats Redis errors as cache
  misses) so a Redis outage degrades to direct DB reads rather than erroring.
  """

  @behaviour AnsibleAppview.Cache
  @conn :appview_redis

  @impl AnsibleAppview.Cache
  def get(key) do
    case Redix.command(@conn, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, bin} when is_binary(bin) -> {:ok, :erlang.binary_to_term(bin)}
      _ -> :miss
    end
  rescue
    _ -> :miss
  end

  @impl AnsibleAppview.Cache
  def put(key, value, ttl_ms) do
    bin = :erlang.term_to_binary(value)
    _ = Redix.command(@conn, ["SET", key, bin, "PX", Integer.to_string(ttl_ms)])
    :ok
  rescue
    _ -> :ok
  end

  @impl AnsibleAppview.Cache
  def delete(key) do
    _ = Redix.command(@conn, ["DEL", key])
    :ok
  rescue
    _ -> :ok
  end
end
