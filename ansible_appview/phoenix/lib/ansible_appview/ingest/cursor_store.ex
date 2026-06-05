defmodule AnsibleAppview.Ingest.CursorStore do
  @moduledoc "Persisted relay-delta ingest cursor."

  alias AnsibleAppview.Repo
  alias AnsibleAppview.Db.IngestCursor

  @source "relay"

  @spec get() :: integer()
  def get(source \\ @source) do
    case Repo.get(IngestCursor, source) do
      nil -> 0
      %IngestCursor{cursor: cursor} -> cursor
    end
  end

  @spec put(integer()) :: :ok
  def put(cursor, source \\ @source) when is_integer(cursor) do
    %IngestCursor{}
    |> IngestCursor.changeset(%{source: source, cursor: cursor})
    |> Repo.insert(
      on_conflict: {:replace, [:cursor, :updated_at]},
      conflict_target: :source
    )

    :ok
  end

  @spec reset() :: :ok
  def reset(source \\ @source) do
    put(0, source)
  end
end
