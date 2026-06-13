defmodule AnsibleRelay.SnapshotStore do
  @moduledoc """
  Signed snapshot generation, lookup, verification, and guarded op retention
  (service architecture plan §Phase 2.3).

  ## Why snapshots

  An AppView (or any consumer) rebuilds its read model by *folding a snapshot*
  then *applying the delta* of ops after the snapshot cursor — instead of
  replaying the full op history. The existing `GET /api/v1/ops/delta?cursor=`
  already serves ops after a cursor; this module produces the snapshot half.

  ## Snapshot format (content-addressed, relay-signed)

  A snapshot is computed over the ops with `ops.id <= cursor`:

    * `cursor`        — inclusive `ops.id` (log_id) the snapshot covers up to.
    * `op_count`      — number of ops in `1..cursor`.
    * `digest`        — `sha256` (hex) over a deterministic, newline-joined list
      of `"<op_id>|<op_cid>"` for every covered op, sorted by `op_id`. `op_cid`
      is the content address of each op (`sha256` over its canonical signed
      fields), so the digest is reproducible by a consumer holding the op set
      and is independent of relay row ordering / ids.
    * `created_at`    — generation time (ISO8601).
    * `snapshot_cid`  — `sha256` (hex) over the canonical snapshot body
      (`cursor`, `op_count`, `digest`). This is the content address and the
      message that is signed. `created_at` is row metadata only and is
      deliberately EXCLUDED so the address is purely content-defined: two
      generations over the identical op set produce the same CID (idempotent),
      and verification has no timestamp-serialization round-trip to worry about.
    * `signature`     — Ed25519 (hex) over `snapshot_cid` by the relay snapshot
      key (`AnsibleRelay.SnapshotSigner`).
    * `signing_public_key_hex` — pinned signer public key for independent verify.

  ## Independent verifiability

  A consumer verifies a snapshot with no relay state:

    1. recompute `digest` from the op set it received (snapshot + delta or full),
    2. recompute `snapshot_cid` from `cursor|op_count|digest`,
    3. check `snapshot_cid` matches and the Ed25519 `signature` verifies against
       `signing_public_key_hex`.

  `verify/1` does exactly this for a stored/returned snapshot map.

  ## Retention (config, OFF by default)

  `:snapshot_retention_days` (app env). Default `:infinity` — nothing is ever
  deleted. When set to an integer N, `prune/0` removes ops that are **all** of:

    * older than N days (`received_at`),
    * covered by the latest published snapshot (`ops.id <= latest.cursor`), and
    * NOT tombstones (`op_type != "delete"`).

  Tombstones (op_type `delete`) and all moderation rows (separate tables) are
  NEVER pruned — they stay authoritative locally per the trust model. Prune is a
  no-op when retention is off or when no snapshot has been published.

  ## Partitioning — DEFERRED (DESIGN TODO, plan §Phase 2.3)

  Physical time-based PostgreSQL partitioning of `ops` is intentionally NOT done
  here: it is a risky live-table migration. Everything in this module works on
  `ops.id` ranges and `received_at`, so it is partition-agnostic — it will keep
  working unchanged once `ops` is later partitioned in its own slice.
  """

  import Ecto.Query
  require Logger

  alias AnsibleRelay.{Metrics, Repo, SnapshotSigner}
  alias AnsibleRelay.Db.{Op, OpSnapshot}

  @tombstone_op_type "delete"

  # --- Generation ---

  @doc """
  Generates and persists a snapshot covering all ops up to the current max
  `ops.id`. Returns `{:ok, snapshot_map}` or `{:error, reason}`.

  Idempotent by content: if an identical snapshot CID already exists it is
  returned without inserting a duplicate.
  """
  @spec generate() :: {:ok, map()} | {:error, atom()}
  def generate do
    cursor = current_max_log_id()
    generate(cursor)
  end

  @doc "Generates a snapshot covering ops with `ops.id <= cursor`."
  @spec generate(non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def generate(cursor) when is_integer(cursor) and cursor >= 0 do
    ops = covered_ops(cursor)
    op_count = length(ops)
    created_at = DateTime.utc_now()
    digest = compute_digest(ops)
    snapshot_cid = compute_cid(cursor, op_count, digest)

    with {:ok, %{signature: signature, public_key_hex: pub_hex}} <-
           SnapshotSigner.sign(snapshot_cid) do
      attrs = %{
        cursor: cursor,
        snapshot_cid: snapshot_cid,
        digest: digest,
        op_count: op_count,
        signature: signature,
        signing_public_key_hex: pub_hex,
        created_at: created_at
      }

      case insert_snapshot(attrs) do
        {:ok, row} ->
          Metrics.inc("relay_snapshot_generated_total")
          Metrics.set("relay_snapshot_cursor", %{}, row.cursor)
          {:ok, to_map(row)}

        {:error, :duplicate} ->
          {:ok, fetch_by_cid(snapshot_cid)}

        {:error, _} = err ->
          err
      end
    end
  end

  def generate(_cursor), do: {:error, :invalid_cursor}

  # --- Lookup ---

  @doc "The most recently generated snapshot (highest cursor), or nil."
  @spec latest() :: map() | nil
  def latest do
    Repo.one(from(s in OpSnapshot, order_by: [desc: s.cursor, desc: s.id], limit: 1))
    |> to_map()
  end

  @doc """
  The newest snapshot at or before `cursor` (so a consumer asking "snapshot near
  log_id X" gets the largest snapshot it can fold then delta from), or nil.
  """
  @spec at_or_before(non_neg_integer()) :: map() | nil
  def at_or_before(cursor) when is_integer(cursor) do
    Repo.one(
      from(s in OpSnapshot,
        where: s.cursor <= ^cursor,
        order_by: [desc: s.cursor, desc: s.id],
        limit: 1
      )
    )
    |> to_map()
  end

  # --- Verification ---

  @doc """
  Independently verifies a snapshot map: recomputes the CID from its body and
  checks the Ed25519 signature against the pinned public key. Does NOT touch the
  database, so a third party can call it with a snapshot it fetched over HTTP.

  Note: this verifies the snapshot's *self-consistency and authenticity*. A
  consumer additionally recomputes `digest` from the op set it folded and checks
  it equals `snapshot["digest"]` to confirm the snapshot describes those ops.
  """
  @spec verify(map()) :: boolean()
  def verify(%{} = snapshot) do
    cursor = get(snapshot, :cursor)
    op_count = get(snapshot, :op_count)
    digest = get(snapshot, :digest)
    cid = get(snapshot, :snapshot_cid)
    signature = get(snapshot, :signature)
    pub_hex = get(snapshot, :signing_public_key_hex)

    with true <- is_integer(cursor) and is_integer(op_count),
         true <- is_binary(digest) and is_binary(cid),
         true <- is_binary(signature) and is_binary(pub_hex),
         recomputed_cid = compute_cid(cursor, op_count, digest),
         true <- recomputed_cid == cid do
      SnapshotSigner.verify(cid, signature, pub_hex)
    else
      _ -> false
    end
  end

  def verify(_), do: false

  @doc """
  Recomputes the deterministic digest over a list of op maps (as served by
  `OpStore.list/1` or `GET /api/v1/ops/delta`). Lets a consumer confirm a folded
  op set matches `snapshot["digest"]`.
  """
  @spec digest_for_ops([map()]) :: String.t()
  def digest_for_ops(ops) when is_list(ops), do: compute_digest_from_maps(ops)

  # --- Retention / prune ---

  @doc """
  Retention window in days, or `:infinity` (default — nothing pruned).
  """
  @spec retention_days() :: pos_integer() | :infinity
  def retention_days do
    case Application.get_env(:ansible_relay, :snapshot_retention_days, :infinity) do
      n when is_integer(n) and n > 0 -> n
      _ -> :infinity
    end
  end

  @doc """
  Guarded prune. Removes ops that are older than the retention window, covered
  by the latest published snapshot, and not tombstones. NEVER prunes tombstones
  or moderation rows. No-op when retention is off or no snapshot exists.

  Returns `{:ok, deleted_count}` or `{:ok, 0}` / `{:noop, reason}`.
  """
  @spec prune() :: {:ok, non_neg_integer()} | {:noop, atom()}
  def prune do
    case retention_days() do
      :infinity ->
        {:noop, :retention_disabled}

      days ->
        case latest() do
          nil ->
            {:noop, :no_snapshot}

          %{cursor: cursor} ->
            cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
            do_prune(cursor, cutoff)
        end
    end
  end

  defp do_prune(cursor, cutoff) do
    {deleted, _} =
      Repo.delete_all(
        from(o in Op,
          where:
            o.id <= ^cursor and
              o.received_at < ^cutoff and
              o.op_type != ^@tombstone_op_type
        )
      )

    if deleted > 0 do
      Logger.info("SnapshotStore.prune removed #{deleted} snapshot-covered ops")
    end

    {:ok, deleted}
  end

  # --- Internals ---

  defp current_max_log_id do
    Repo.one(from(o in Op, select: max(o.id))) || 0
  end

  defp covered_ops(cursor) do
    Repo.all(
      from(o in Op,
        where: o.id <= ^cursor,
        order_by: [asc: o.id],
        select: %{
          op_id: o.op_id,
          author_did: o.author_did,
          entity_type: o.entity_type,
          entity_id: o.entity_id,
          op_type: o.op_type,
          payload: o.payload,
          signature: o.signature,
          schema_version: o.schema_version
        }
      )
    )
  end

  # Per-op content address: sha256 over the op's canonical signed fields. Stable
  # across relays and independent of local row ids / receive order.
  defp op_cid(op) do
    canonical =
      [
        op[:author_did] || op["author_did"],
        op[:entity_id] || op["entity_id"],
        op[:entity_type] || op["entity_type"],
        op[:op_id] || op["op_id"],
        op[:op_type] || op["op_type"],
        op[:payload] || op["payload"],
        op[:signature] || op["signature"]
      ]
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")

    :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
  end

  defp compute_digest(ops), do: compute_digest_from_maps(ops)

  defp compute_digest_from_maps(ops) do
    body =
      ops
      |> Enum.map(fn op ->
        op_id = op[:op_id] || op["op_id"]
        "#{op_id}|#{op_cid(op)}"
      end)
      |> Enum.sort()
      |> Enum.join("\n")

    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  # Content address over the snapshot's content only (cursor, op_count,
  # digest). `created_at` is intentionally excluded — it is row metadata, not
  # content — so identical op sets yield identical CIDs (idempotent generation)
  # and HTTP-fetched snapshots verify without timestamp round-trip concerns.
  defp compute_cid(cursor, op_count, digest) do
    body =
      [
        "cursor=#{cursor}",
        "op_count=#{op_count}",
        "digest=#{digest}"
      ]
      |> Enum.join("\n")

    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  defp insert_snapshot(attrs) do
    case %OpSnapshot{} |> OpSnapshot.changeset(attrs) |> Repo.insert() do
      {:ok, row} ->
        {:ok, row}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :snapshot_cid) do
          {:error, :duplicate}
        else
          Logger.warning("SnapshotStore: insert failed: #{inspect(errors)}")
          {:error, :insert_failed}
        end
    end
  end

  defp fetch_by_cid(cid) do
    Repo.one(from(s in OpSnapshot, where: s.snapshot_cid == ^cid)) |> to_map()
  end

  defp to_map(nil), do: nil

  defp to_map(%OpSnapshot{} = s) do
    %{
      cursor: s.cursor,
      snapshot_cid: s.snapshot_cid,
      digest: s.digest,
      op_count: s.op_count,
      signature: s.signature,
      signing_public_key_hex: s.signing_public_key_hex,
      created_at: s.created_at && DateTime.to_iso8601(s.created_at)
    }
  end

  defp get(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
