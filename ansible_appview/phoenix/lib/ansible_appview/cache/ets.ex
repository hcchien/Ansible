defmodule AnsibleAppview.Cache.ETS do
  @moduledoc """
  In-process ETS cache adapter (default). The GenServer owns a public table;
  get/put run directly in the caller. Entries expire lazily on read by TTL, and
  the owning GenServer also runs a periodic sweep that deletes all expired rows
  — without it, keys written but never re-read (e.g. `item:{op_id}` rows written
  for every folded op, folder.ex fan-out) would accumulate until expiry only if
  something read them, i.e. effectively forever. Correct for a single AppView
  instance; use the Redix adapter for multiple.
  """

  @behaviour AnsibleAppview.Cache
  use GenServer
  require Logger

  @table :ansible_appview_cache
  @default_sweep_interval_ms 60_000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    sweep_expired()
    schedule_sweep()
    {:noreply, state}
  end

  @doc "Deletes every entry whose TTL has elapsed. Returns the count removed."
  def sweep_expired do
    # match_delete on rows whose expires_at is <= now (guard `:"$3" <= now`).
    now = now_ms()
    :ets.select_delete(@table, [{{:_, :_, :"$3"}, [{:"=<", :"$3", now}], [true]}])
  rescue
    ArgumentError -> 0
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, sweep_interval_ms())
  end

  defp sweep_interval_ms do
    Application.get_env(:ansible_appview, :cache_sweep_interval_ms, @default_sweep_interval_ms)
  end

  @impl AnsibleAppview.Cache
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if expires_at > now_ms() do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  @impl AnsibleAppview.Cache
  def put(key, value, ttl_ms) do
    :ets.insert(@table, {key, value, now_ms() + ttl_ms})
    :ok
  end

  @impl AnsibleAppview.Cache
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
