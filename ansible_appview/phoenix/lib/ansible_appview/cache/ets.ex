defmodule AnsibleAppview.Cache.ETS do
  @moduledoc """
  In-process ETS cache adapter (default). The GenServer owns a public table;
  get/put run directly in the caller. Entries expire lazily on read by TTL.
  Correct for a single AppView instance; use the Redix adapter for multiple.
  """

  @behaviour AnsibleAppview.Cache
  use GenServer

  @table :ansible_appview_cache

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

    {:ok, state}
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

  defp now_ms, do: System.monotonic_time(:millisecond)
end
