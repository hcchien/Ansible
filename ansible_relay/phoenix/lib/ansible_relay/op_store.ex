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
    do_append(op)
  end

  @doc """
  Append an update/delete only when its signer created the entity.

  When [expected_previous_revision] is supplied, the append is additionally
  compare-and-swap protected against the entity's latest op id.  The advisory
  transaction lock makes the author/revision check and insert one serialized
  decision for this entity; this is important because a UI-side revision check
  alone can be raced by another signed write.
  """
  def append_author_mutation(op, expected_previous_revision \\ nil) do
    Repo.transaction(fn ->
      lock_entity(op.entity_type, op.entity_id)

      result =
        with :ok <- verify_original_author(op),
             :ok <- verify_previous_revision(op, expected_previous_revision) do
          do_append(op)
        end

      case result do
        {:ok, log_id} -> log_id
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, log_id} -> {:ok, log_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Append the first active reaction for an author/target pair.

  This lock is intentionally keyed by the semantic reaction target rather
  than the client-generated entity id, so concurrent devices cannot create
  two countable reactions for the same user and target.
  """
  def append_reaction_insert(op, target_type, target_id) do
    Repo.transaction(fn ->
      lock_reaction(op.author_did, target_type, target_id)

      if active_reaction_exists?(op.author_did, target_type, target_id) do
        Repo.rollback(:active_reaction_exists)
      else
        case do_append(op) do
          {:ok, log_id} -> log_id
          {:error, reason} -> Repo.rollback(reason)
        end
      end
    end)
    |> case do
      {:ok, log_id} -> {:ok, log_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_append(op) do
    attrs = %{
      op_id: op.op_id,
      author_did: op.author_did,
      entity_type: op.entity_type,
      entity_id: op.entity_id,
      op_type: op.op_type,
      payload: op.payload,
      signature: op.signature,
      schema_version: Map.get(op, :schema_version, 1),
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

  @doc """
  List ops after a given log_id cursor (indexed primary-key range scan).

  ## Sequence-gap safety

  `id` is a bigserial: a transaction reserves its id when it inserts, but
  commits independently. So a delta read can observe a committed `id = N` while
  a concurrent transaction that reserved `id = N - 1` earlier is still
  uncommitted. A naive `WHERE id > cursor` would serve `N`, advance the
  consumer's cursor past `N`, and permanently skip `N - 1` once it commits.

  To close that gap we hold back any row at or above the first *not-yet-settled*
  id. A row is "settled" once its inserting transaction id (`xmin`) is strictly
  below the current snapshot's xmin — at that point every transaction with a
  lower xid has committed or aborted, so no lower-id row can still appear. The
  watermark is the lowest id whose `xmin` is still at/above the snapshot xmin;
  we only serve `id < watermark`, which is monotonic and never skips a gap.
  """
  def list(after_log_id: cursor, limit: limit) do
    query =
      if settle_guard_enabled?() do
        from(o in Op,
          where: o.id > ^cursor and o.id < subquery(settle_watermark()),
          order_by: [asc: o.id],
          limit: ^limit
        )
      else
        # The settle guard relies on transaction xids to detect uncommitted
        # lower-id rows. The Ecto SQL sandbox wraps each statement in a
        # savepoint (subtransaction), giving inserted rows a subtransaction
        # xmin distinct from the top-level xid, so the guard would hide a
        # test's own just-inserted rows. Sandboxed tests set
        # :op_store_settle_guard to false; the raw-connection gap test exercises
        # the real guarded SQL instead. Never disable this outside tests.
        from(o in Op,
          where: o.id > ^cursor,
          order_by: [asc: o.id],
          limit: ^limit
        )
      end

    query
    |> Repo.all()
    |> Enum.map(&to_op_map/1)
  end

  defp settle_guard_enabled? do
    Application.get_env(:ansible_relay, :op_store_settle_guard, true)
  end

  # Lowest id that is not yet guaranteed settled. Any row with an id below this
  # is committed and can never be preceded by a still-pending lower id. When no
  # unsettled rows exist the watermark is max(id) + 1 so the whole log is
  # servable. `xmin::text::xid8` widens the 32-bit row xid for comparison
  # against pg_snapshot_xmin (an xid8); acceptable for a short settle horizon.
  #
  # A row is "unsettled" when its inserting transaction id (xmin) is at/above the
  # current snapshot's xmin — i.e. that transaction may still be in flight, so a
  # lower id could still appear. Holding back everything at/above the lowest such
  # id makes the served window monotonic and gap-free.
  defp settle_watermark do
    from(o in Op,
      select:
        coalesce(
          min(o.id),
          fragment("(SELECT COALESCE(MAX(id), 0) + 1 FROM ops)")
        ),
      where:
        fragment(
          "?::text::xid8 >= pg_snapshot_xmin(pg_current_snapshot())",
          fragment("xmin")
        )
    )
  end

  @doc "Check if an op_id has already been processed (indexed unique lookup)."
  def exists?(op_id) do
    Repo.exists?(from(o in Op, where: o.op_id == ^op_id))
  end

  @doc "Returns one accepted op by its globally unique op id."
  def get_by_op_id(op_id) when is_binary(op_id) do
    from(o in Op, where: o.op_id == ^op_id, limit: 1)
    |> Repo.one()
    |> case do
      nil -> nil
      row -> to_op_map(row)
    end
  end

  @doc "Lists an author's ops after a cursor without exposing other authors."
  def list_by_author(author_did, after_log_id: cursor, limit: limit)
      when is_binary(author_did) do
    from(o in Op,
      where: o.author_did == ^author_did and o.id > ^cursor,
      order_by: [asc: o.id],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&to_op_map/1)
  end

  @doc "Lists relationship ops for one follower/target pair newest first."
  def follow_ops(follower_did, target_did) do
    from(o in Op,
      where:
        (o.entity_type == "follow" and o.author_did == ^follower_did and
           o.entity_id == ^target_did) or
          (o.entity_type == "follow_grant" and o.author_did == ^target_did and
             o.entity_id == ^follower_did),
      order_by: [desc: o.id]
    )
    |> Repo.all()
    |> Enum.map(&to_op_map/1)
  end

  @doc "Lists recent follow requests targeting one DID."
  def follow_requests_for(target_did, limit \\ 200) when is_binary(target_did) do
    from(o in Op,
      where: o.entity_type == "follow" and o.entity_id == ^target_did,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&to_op_map/1)
  end

  @doc "True when the op log contains host-visible approved-follower content."
  def followers_content_exists? do
    from(o in Op,
      where: o.entity_type in ["murmur", "note"],
      select: o.payload
    )
    |> Repo.all()
    |> Enum.any?(fn payload ->
      case decode_payload(payload) do
        %{"visibility" => "followers"} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Author DID of the create (`insert`) op for an entity, or nil.

  Used by wake scheduling to resolve a reply's parent-thread author without
  reading any content fields.
  """
  def create_op_author(entity_type, entity_id) do
    Repo.one(
      from(o in Op,
        where:
          o.entity_type == ^entity_type and o.entity_id == ^entity_id and
            o.op_type == "insert",
        order_by: [asc: o.id],
        limit: 1,
        select: o.author_did
      )
    )
  end

  defp lock_entity(entity_type, entity_id) do
    # `hashtext` collisions merely serialize unrelated entities; they cannot
    # authorize a mutation.  The lock is released with this transaction.
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["#{entity_type}:#{entity_id}"])
    :ok
  end

  defp lock_reaction(author_did, target_type, target_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
      "reaction:#{author_did}:#{target_type}:#{target_id}"
    ])

    :ok
  end

  defp active_reaction_exists?(author_did, target_type, target_id) do
    from(o in Op,
      where:
        o.author_did == ^author_did and o.entity_type == "reaction" and o.op_type == "insert",
      select: {o.entity_id, o.payload}
    )
    |> Repo.all()
    |> Enum.any?(fn {entity_id, payload} ->
      reaction_target?(payload, target_type, target_id) and reaction_active?(entity_id)
    end)
  end

  defp reaction_target?(payload, target_type, target_id) do
    with {:ok, %{} = map} <- decode_reaction_payload(payload) do
      map["targetType"] == target_type and map["targetId"] == target_id
    else
      _ -> false
    end
  end

  # Direct Relay sync operations are base64 JSON. Web publication operations
  # historically stored JSON directly, so accept both while enforcing the same
  # semantic author/target invariant for every ingress path.
  defp decode_reaction_payload(payload) do
    case Base.decode64(payload) do
      {:ok, decoded} -> Jason.decode(decoded)
      :error -> Jason.decode(payload)
    end
  end

  defp reaction_active?(entity_id) do
    Repo.one(
      from(o in Op,
        where: o.entity_type == "reaction" and o.entity_id == ^entity_id,
        order_by: [desc: o.id],
        limit: 1,
        select: o.op_type
      )
    ) != "delete"
  end

  defp verify_original_author(op) do
    author_did = op.author_did

    case create_op_author(op.entity_type, op.entity_id) do
      ^author_did -> :ok
      nil -> {:error, :original_content_not_found}
      _ -> {:error, :not_original_author}
    end
  end

  defp verify_previous_revision(_op, nil), do: :ok

  defp verify_previous_revision(op, expected_previous_revision)
       when is_binary(expected_previous_revision) do
    latest_revision =
      Repo.one(
        from(o in Op,
          where: o.entity_type == ^op.entity_type and o.entity_id == ^op.entity_id,
          order_by: [desc: o.id],
          limit: 1,
          select: o.op_id
        )
      )

    if latest_revision == expected_previous_revision,
      do: :ok,
      else: {:error, :revision_conflict}
  end

  @doc """
  The create (`insert`) op for an entity as a served op map, or nil.

  Used by the thread-preview endpoint to read a thread's title/author without
  a delta scan.
  """
  def create_op(entity_type, entity_id) do
    from(o in Op,
      where:
        o.entity_type == ^entity_type and o.entity_id == ^entity_id and
          o.op_type == "insert",
      order_by: [asc: o.id],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> nil
      row -> to_op_map(row)
    end
  end

  @doc """
  Reply stats for a thread: `{count, first_reply_op_map | nil}` over post
  insert ops whose payload `threadId` is the given thread. The payload column
  is text, so the filter casts through jsonb (invalid-JSON rows are impossible
  past ingest validation).
  """
  def thread_reply_stats(thread_id) do
    base =
      from(o in Op,
        where:
          o.entity_type == "post" and o.op_type == "insert" and
            fragment("(?::jsonb ->> 'threadId') = ?", o.payload, ^thread_id)
      )

    count = Repo.aggregate(base, :count)

    first =
      from(o in base, order_by: [asc: o.id], limit: 1)
      |> Repo.one()
      |> case do
        nil -> nil
        row -> to_op_map(row)
      end

    {count, first}
  end

  # --- GenServer (vestigial: supervision compatibility only) ---

  @impl true
  def init(state), do: {:ok, state}

  # --- Helpers ---

  def to_op_map(%Op{} = o) do
    %{
      log_id: o.id,
      op_id: o.op_id,
      author_did: o.author_did,
      entity_type: o.entity_type,
      entity_id: o.entity_id,
      op_type: o.op_type,
      payload: o.payload,
      signature: o.signature,
      schema_version: o.schema_version || 1,
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

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = value} ->
        value

      _ ->
        case Base.decode64(payload) do
          {:ok, decoded} ->
            case Jason.decode(decoded) do
              {:ok, %{} = value} -> value
              _ -> %{}
            end

          :error ->
            %{}
        end
    end
  end

  defp decode_payload(_), do: %{}
end
