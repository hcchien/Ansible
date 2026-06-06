defmodule AnsibleAppview.HomeTimeline.ETS do
  @moduledoc """
  In-process ETS home-timeline adapter (default, single instance). An
  `ordered_set` keyed by `{reader_did, log_id}` gives ordered range reads per
  reader. The GenServer owns the table; reads/writes run in the caller.
  """

  @behaviour AnsibleAppview.HomeTimeline
  use GenServer

  @table :appview_home_timeline

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    :ets.new(@table, [
      :named_table,
      :public,
      :ordered_set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, state}
  end

  @impl AnsibleAppview.HomeTimeline
  def add(reader, log_id, op_id) do
    :ets.insert(@table, {{reader, log_id}, op_id})
    :ok
  end

  @impl AnsibleAppview.HomeTimeline
  def add_many(entries) do
    rows = Enum.map(entries, fn {reader, log_id, op_id} -> {{reader, log_id}, op_id} end)
    :ets.insert(@table, rows)
    :ok
  end

  @impl AnsibleAppview.HomeTimeline
  def range(reader, cursor, limit) do
    guard =
      case cursor do
        nil -> []
        c -> [{:<, :"$1", c}]
      end

    spec = [{{{reader, :"$1"}, :"$2"}, guard, [{{:"$1", :"$2"}}]}]

    :ets.select(@table, spec)
    |> Enum.sort_by(fn {log_id, _} -> log_id end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {log_id, op_id} -> %{log_id: log_id, op_id: op_id} end)
  end

  @impl AnsibleAppview.HomeTimeline
  def cap(reader, max) do
    keys =
      :ets.select(@table, [{{{reader, :"$1"}, :_}, [], [:"$1"]}])
      |> Enum.sort(:desc)

    keys
    |> Enum.drop(max)
    |> Enum.each(fn log_id -> :ets.delete(@table, {reader, log_id}) end)

    :ok
  end

  @impl AnsibleAppview.HomeTimeline
  def exists?(reader) do
    case :ets.select(@table, [{{{reader, :_}, :_}, [], [true]}], 1) do
      {[_], _cont} -> true
      _ -> false
    end
  end
end
