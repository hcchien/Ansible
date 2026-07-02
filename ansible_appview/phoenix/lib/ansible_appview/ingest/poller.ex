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
    {:ok, %{interval: interval, consecutive_failures: 0}}
  end

  @impl true
  def handle_info(:poll, state) do
    # A single poison op is skipped inside Folder (dead-lettered), so a drain
    # normally makes progress. This loop still guards against a drain-level
    # failure (relay fetch error, an exception, or a task EXIT that `rescue`
    # does not catch) so one bad poll never crashes the poller — and tracks a
    # consecutive-failure gauge so a persistently stuck drain is alertable.
    result =
      try do
        Rebuilder.drain()
      rescue
        e ->
          Logger.warning("AppView poll error: #{inspect(e)}")
          {:error, e}
      catch
        :exit, reason ->
          Logger.warning("AppView poll exited: #{inspect(reason)}")
          {:error, {:exit, reason}}
      end

    failures =
      case result do
        {:ok, _} -> 0
        _ -> state.consecutive_failures + 1
      end

    AnsibleAppview.Metrics.set("appview_ingest_drain_consecutive_failures", %{}, failures)

    schedule(state.interval)
    {:noreply, %{state | consecutive_failures: failures}}
  end

  defp schedule(after_ms) do
    Process.send_after(self(), :poll, after_ms)
  end
end
