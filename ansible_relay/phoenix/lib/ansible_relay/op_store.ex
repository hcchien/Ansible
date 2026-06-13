defmodule AnsibleRelay.OpStore do
  @moduledoc """
  PostgreSQL-backed Op log (Comp C).

  Ops are appended with concurrent `INSERT`s (no single-writer process), deltas
  are served by indexed cursor scans on the primary key, and duplicate op_ids
  are rejected atomically by the `ops_op_id_index` unique constraint. There is no
  in-memory copy of the op history, so memory is bounded and read/write
  throughput scales with the database rather than a single GenServer mailbox.

  The trivial GenServer is retained only so the module remains a supervised child
  with a stable `start_link/1`; it holds no state and is never on the hot path.
  """

  use GenServer
  require Logger

  import Ecto.Query
  alias AnsibleRelay.{Repo, Db.Op}

  # --- Public API ---

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Append an Op. Returns `{:ok, log_id}` or `{:error, :duplicate}`.

  Concurrent and lock-free: duplicate op_ids are caught by the unique index, so
  this is safe under parallel ingest without a serializing process.
  """
  def append(op) do
    attrs = %{
      op_id: op.op_id,
      author_did: op.author_did,
      entity_type: op.entity_type,
      entity_id: op.entity_id,
      op_type: op.op_type,
      payload: op.payload,
      signature: op.signature,
      received_at: received_at(op)
    }

    case %Op{} |> Op.changeset(attrs) |> Repo.insert() do
      {:ok, row} ->
        {:ok, row.id}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :op_id) do
          {:error, :duplicate}
        else
          Logger.warning("OpStore: insert failed for op_id=#{op.op_id}: #{inspect(errors)}")
          {:error, :insert_failed}
        end
    end
  end

  @doc "List ops after a given log_id cursor (indexed primary-key range scan)."
  def list(after_log_id: cursor, limit: limit) do
    Repo.all(
      from o in Op,
        where: o.id > ^cursor,
        order_by: [asc: o.id],
        limit: ^limit
    )
    |> Enum.map(&to_op_map/1)
  end

  @doc "Check if an op_id has already been processed (indexed unique lookup)."
  def exists?(op_id) do
    Repo.exists?(from o in Op, where: o.op_id == ^op_id)
  end

  @doc """
  Author DID of the create (`insert`) op for an entity, or nil.

  Used by wake scheduling to resolve a reply's parent-thread author without
  reading any content fields.
  """
  def create_op_author(entity_type, entity_id) do
    Repo.one(
      from o in Op,
        where:
          o.entity_type == ^entity_type and o.entity_id == ^entity_id and
            o.op_type == "insert",
        order_by: [asc: o.id],
        limit: 1,
        select: o.author_did
    )
  end

  # --- GenServer (vestigial: supervision compatibility only) ---

  @impl true
  def init(state), do: {:ok, state}

  # --- Helpers ---

  defp to_op_map(%Op{} = o) do
    %{
      log_id: o.id,
      op_id: o.op_id,
      author_did: o.author_did,
      entity_type: o.entity_type,
      entity_id: o.entity_id,
      op_type: o.op_type,
      payload: o.payload,
      signature: o.signature,
      received_at: o.received_at && DateTime.to_iso8601(o.received_at)
    }
  end

  defp received_at(op) do
    case Map.get(op, :received_at) do
      %DateTime{} = dt -> dt
      value when is_binary(value) -> parse_received_at(value)
      _ -> DateTime.utc_now()
    end
  end

  defp parse_received_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
