defmodule AnsibleAppview.HomeTimeline do
  @moduledoc """
  Per-reader materialized home timeline (fan-out-on-write target). Stores only
  references — `{log_id, op_id}` — newest-first by `log_id`; content is hydrated
  separately. A reproducible projection: a reader's timeline can be rebuilt from
  `feed_items` + the follow graph, so the store may be a cache.

  Pluggable adapter: in-process ETS (default, single instance) or a Redis ZSET
  (`htl:{reader}`, score=log_id, member=op_id) when `REDIS_URL` is configured.
  """

  @type entry :: %{log_id: integer(), op_id: String.t()}

  @callback add(reader_did :: String.t(), log_id :: integer(), op_id :: String.t()) :: :ok
  @callback add_many([{String.t(), integer(), String.t()}]) :: :ok
  @callback range(reader_did :: String.t(), cursor :: integer() | nil, limit :: pos_integer()) ::
              [entry()]
  @callback cap(reader_did :: String.t(), max :: pos_integer()) :: :ok
  @callback exists?(reader_did :: String.t()) :: boolean()

  def add(reader, log_id, op_id), do: adapter().add(reader, log_id, op_id)
  def add_many(entries), do: adapter().add_many(entries)
  def range(reader, cursor, limit), do: adapter().range(reader, cursor, limit)
  def cap(reader, max), do: adapter().cap(reader, max)
  def exists?(reader), do: adapter().exists?(reader)

  @doc "Max entries kept per reader timeline."
  def max_entries, do: Application.get_env(:ansible_appview, :home_timeline_max, 800)

  defp adapter do
    Application.get_env(:ansible_appview, :home_timeline_adapter, AnsibleAppview.HomeTimeline.ETS)
  end
end
