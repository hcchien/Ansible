defmodule AnsibleAppview.HomeTimeline.Redix do
  @moduledoc """
  Redis ZSET home-timeline adapter (multi-instance). One sorted set per reader:
  `htl:{reader}` with score=log_id, member=op_id. Enabled when `REDIS_URL` is set
  (connection `:appview_redis`). Reads fail open to an empty list so a Redis
  outage degrades to the fan-out-on-read fallback rather than erroring.
  """

  @behaviour AnsibleAppview.HomeTimeline
  @conn :appview_redis

  defp key(reader), do: "htl:" <> reader

  @impl AnsibleAppview.HomeTimeline
  def add(reader, log_id, op_id) do
    _ = Redix.command(@conn, ["ZADD", key(reader), Integer.to_string(log_id), op_id])
    :ok
  rescue
    _ -> :ok
  end

  @impl AnsibleAppview.HomeTimeline
  def add_many(entries) do
    entries
    |> Enum.group_by(fn {reader, _, _} -> reader end)
    |> Enum.each(fn {reader, group} ->
      args =
        Enum.flat_map(group, fn {_, log_id, op_id} ->
          [Integer.to_string(log_id), op_id]
        end)

      _ = Redix.command(@conn, ["ZADD", key(reader) | args])
    end)

    :ok
  rescue
    _ -> :ok
  end

  @impl AnsibleAppview.HomeTimeline
  def range(reader, cursor, limit) do
    max = if is_integer(cursor) and cursor > 0, do: "(" <> Integer.to_string(cursor), else: "+inf"

    case Redix.command(@conn, [
           "ZREVRANGEBYSCORE",
           key(reader),
           max,
           "-inf",
           "WITHSCORES",
           "LIMIT",
           "0",
           Integer.to_string(limit)
         ]) do
      {:ok, flat} when is_list(flat) ->
        flat
        |> Enum.chunk_every(2)
        |> Enum.map(fn [op_id, score] ->
          %{log_id: String.to_integer(score), op_id: op_id}
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @impl AnsibleAppview.HomeTimeline
  def cap(reader, max) do
    # Keep the highest-scored `max` members; remove the rest (lowest ranks).
    _ = Redix.command(@conn, ["ZREMRANGEBYRANK", key(reader), "0", Integer.to_string(-max - 1)])
    :ok
  rescue
    _ -> :ok
  end

  @impl AnsibleAppview.HomeTimeline
  def exists?(reader) do
    case Redix.command(@conn, ["EXISTS", key(reader)]) do
      {:ok, 1} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
