defmodule AnsibleAppview.Ingest.ExternalPoller do
  @moduledoc """
  Background worker for inbound federation (design 2026-06-13): on an interval,
  pulls each enabled curated `ExternalSource`'s public outbox via
  `ExternalIngest.ingest_source/1`.

  Pull-only, allowlist-bounded — there is no inbound `/inbox` endpoint (that is an
  unbounded abuse surface, explicitly out of scope; see design D2).

  Interval is `:external_ingest_interval_ms`; default is large/off so it never
  fires during tests (tests call `ExternalIngest.ingest_source/1` directly). Each
  source is ingested independently and failure-tolerantly — one source erroring
  never crashes the loop or affects native firehose ingest.
  """

  use GenServer
  require Logger

  alias AnsibleAppview.ExternalSources
  alias AnsibleAppview.Ingest.{CursorStore, ExternalIngest, RelayClient}

  # Default OFF (0 = never schedule) so tests and unconfigured deployments don't
  # poll the fediverse implicitly.
  @default_interval_ms 0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, interval_ms())

    if interval > 0 do
      Process.send_after(self(), :poll, interval)
    end

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:poll, %{interval: interval} = state) do
    poll_all()
    if interval > 0, do: Process.send_after(self(), :poll, interval)
    {:noreply, state}
  end

  @doc "Ingest every enabled source once. Safe to call directly. Never raises."
  @spec poll_all() :: :ok
  def poll_all do
    poll_relay_inbox()

    ExternalSources.list_enabled()
    |> Enum.each(fn source ->
      try do
        ExternalIngest.ingest_source(source)
      rescue
        e ->
          Logger.warning("external poller error for #{source.actor_uri}: #{inspect(e)}")
      end
    end)

    :ok
  rescue
    e ->
      Logger.warning("external poller poll_all error: #{inspect(e)}")
      :ok
  end

  defp poll_relay_inbox do
    base_url = Application.fetch_env!(:ansible_appview, :relay_base_url)
    source = "activitypub_inbound"
    cursor = CursorStore.get(source)

    case RelayClient.fetch_federation_inbound(base_url, cursor) do
      {:ok, page} ->
        Enum.each(page.activities, &ExternalIngest.ingest_activity/1)
        CursorStore.put(page.next_cursor, source)
        if page.has_more, do: poll_relay_inbox()

      {:error, reason} ->
        Logger.warning("ActivityPub inbound delta fetch failed: #{inspect(reason)}")
    end
  end

  defp interval_ms do
    Application.get_env(:ansible_appview, :external_ingest_interval_ms, @default_interval_ms)
  end
end
