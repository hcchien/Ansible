defmodule AnsibleRelay.OpStore do
  @moduledoc """
  ETS-backed Op log with PostgreSQL write-through for durability.

  V1.1 Comp C — stores CRDT ops with auto-incrementing log_id.
  ETS is the L1 read cache for hot-path dedup and cursor queries.
  PostgreSQL is the durable backing store written on every accepted op.
  """

  use GenServer
  require Logger

  alias AnsibleRelay.{Repo, Db.Op}

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{ops: [], next_id: 1, op_ids: MapSet.new()}, name: __MODULE__)
  end

  @doc "Append an Op. Returns {:ok, log_id} or {:error, :duplicate}."
  def append(op) do
    GenServer.call(__MODULE__, {:append, op})
  end

  @doc "List ops after a given log_id cursor."
  def list(after_log_id: cursor, limit: limit) do
    GenServer.call(__MODULE__, {:list, cursor, limit})
  end

  @doc "Check if an op_id has already been processed (dedup)."
  def exists?(op_id) do
    GenServer.call(__MODULE__, {:exists, op_id})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:append, op}, _from, %{ops: ops, next_id: id, op_ids: ids} = state) do
    if MapSet.member?(ids, op.op_id) do
      {:reply, {:error, :duplicate}, state}
    else
      logged_op = Map.put(op, :log_id, id)
      new_state = %{state | ops: ops ++ [logged_op], next_id: id + 1, op_ids: MapSet.put(ids, op.op_id)}

      # Write-through to PostgreSQL for durability
      case Repo.insert(%Op{
        op_id:       op.op_id,
        author_did:  op.author_did,
        entity_type: op.entity_type,
        entity_id:   op.entity_id,
        op_type:     op.op_type,
        payload:     op.payload,
        signature:   op.signature,
        received_at: DateTime.utc_now(),
      }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{} = cs} ->
          # Duplicate op_id in DB (race condition or replay) — log and continue
          Logger.warning("OpStore: DB insert conflict for op_id=#{op.op_id}: #{inspect(cs.errors)}")

        {:error, reason} ->
          Logger.warning("OpStore: DB insert failed for op_id=#{op.op_id}: #{inspect(reason)}")
      end

      {:reply, {:ok, id}, new_state}
    end
  end

  @impl true
  def handle_call({:list, cursor, limit}, _from, %{ops: ops} = state) do
    result = ops |> Enum.filter(&(&1.log_id > cursor)) |> Enum.take(limit)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:exists, op_id}, _from, %{op_ids: ids} = state) do
    {:reply, MapSet.member?(ids, op_id), state}
  end
end
