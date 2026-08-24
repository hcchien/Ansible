defmodule AnsibleAppview.Ingest.Rebuilder do
  @moduledoc """
  Drains the relay op stream from cursor 0 into the projection. Used both by the
  one-shot rebuild (after truncating) and as the shared pull loop.
  """

  require Logger
  alias AnsibleAppview.Repo
  alias AnsibleAppview.Ingest.{CursorStore, Folder, RelayClient}

  @doc "Truncates the projection, resets the cursor, then drains from the relay."
  def run do
    # All three tables are disposable projections of the public Relay stream.
    # Rebuilding only feed_items previously left stale profile rows behind.
    Repo.query!("TRUNCATE TABLE feed_items, appview_profiles, appview_follows")
    CursorStore.reset()
    drain()
  end

  @doc "Pulls and folds pages from the saved cursor until the relay has no more."
  def drain(base_url \\ nil, max_pages \\ 100_000) do
    base = base_url || Application.fetch_env!(:ansible_appview, :relay_base_url)
    do_drain(base, max_pages, 0)
  end

  defp do_drain(_base, 0, total), do: {:ok, total}

  defp do_drain(base, pages_left, total) do
    cursor = CursorStore.get()

    case RelayClient.fetch_delta(base, cursor) do
      {:ok, %{ops: ops, next_cursor: next_cursor, has_more: has_more}} ->
        {indexed, _max_log} = Folder.apply_ops(ops)
        if next_cursor > cursor, do: CursorStore.put(next_cursor)

        cond do
          has_more and next_cursor > cursor -> do_drain(base, pages_left - 1, total + indexed)
          true -> {:ok, total + indexed}
        end

      {:error, reason} ->
        Logger.warning("AppView ingest drain stopped: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
