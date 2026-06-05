defmodule AnsibleAppview.Ingest.Poller do
  @moduledoc """
  Background worker: periodically drains the relay op delta into the projection.
  The AppView is the single firehose consumer (Phase B — no Pub/Sub).
  """

  use GenServer
  require Logger
  alias AnsibleAppview.Ingest.Rebuilder

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    interval = Application.get_env(:ansible_appview, :ingest_interval_ms, 5_000)
    schedule(0)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:poll, state) do
    try do
      Rebuilder.drain()
    rescue
      e -> Logger.warning("AppView poll error: #{inspect(e)}")
    end

    schedule(state.interval)
    {:noreply, state}
  end

  defp schedule(after_ms) do
    Process.send_after(self(), :poll, after_ms)
  end
end
