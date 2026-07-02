defmodule AnsibleAppview.HomeTimeline.ETS do
  @moduledoc """
  In-process ETS home-timeline adapter (default, single instance). An
  `ordered_set` keyed by `{reader_did, log_id}` gives ordered range reads per
  reader. The GenServer owns the table; reads/writes run in the caller.

  Each reader's entries are capped (`HomeTimeline.cap/2`), but the *set of
  readers* was unbounded. The owning GenServer runs a periodic sweep that evicts
  the stalest readers once the distinct-reader count exceeds
  `:home_timeline_reader_cap`, keeping the table bounded on a long-running node.
  """

  @behaviour AnsibleAppview.HomeTimeline
  use GenServer
  require Logger

  @table :appview_home_timeline
  @default_sweep_interval_ms 300_000
  @default_reader_cap 50_000

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

    schedule_sweep()
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    sweep_readers()
    schedule_sweep()
    {:noreply, state}
  end

  @doc """
  Evict the stalest readers when the distinct-reader count exceeds the cap. A
  reader's staleness is its newest `log_id` (lowest = stalest). Returns the
  number of readers evicted.
  """
  def sweep_readers do
    cap = reader_cap()

    # Newest log_id per reader.
    newest =
      :ets.foldl(
        fn {{reader, log_id}, _op_id}, acc ->
          Map.update(acc, reader, log_id, &max(&1, log_id))
        end,
        %{},
        @table
      )

    if map_size(newest) <= cap do
      0
    else
      to_evict =
        newest
        |> Enum.sort_by(fn {_reader, newest_log} -> newest_log end)
        |> Enum.take(map_size(newest) - cap)
        |> Enum.map(fn {reader, _} -> reader end)

      Enum.each(to_evict, fn reader ->
        :ets.match_delete(@table, {{reader, :_}, :_})
      end)

      length(to_evict)
    end
  rescue
    ArgumentError -> 0
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, sweep_interval_ms())

  defp sweep_interval_ms,
    do:
      Application.get_env(
        :ansible_appview,
        :home_timeline_sweep_interval_ms,
        @default_sweep_interval_ms
      )

  defp reader_cap,
    do: Application.get_env(:ansible_appview, :home_timeline_reader_cap, @default_reader_cap)

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
