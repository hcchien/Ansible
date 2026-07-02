defmodule AnsibleRelay.OpStoreGapTest do
  @moduledoc """
  Demonstrates the firehose cursor sequence-gap fix (OpStore.list/1).

  `id` is a bigserial: a later-committing transaction can hold a *lower* id than
  an already-committed one. A naive `WHERE id > cursor` would serve the higher
  id, advance the consumer's cursor past it, and permanently skip the lower id
  once it commits. The settle-watermark guard must hold back everything at/above
  the first not-yet-committed id.

  This test runs three raw Postgrex connections OUTSIDE the Ecto sandbox (the
  sandbox pins everything to one connection, which cannot reproduce a real
  cross-transaction gap). It cleans up the rows it inserts.
  """
  use ExUnit.Case, async: false

  @moduletag :gap

  # Mirrors AnsibleRelay.OpStore.list/1's guarded range scan so the test can run
  # it on a raw connection (OpStore.list goes through the sandboxed Repo, which
  # cannot observe a cross-connection gap). If OpStore.list's SQL changes, this
  # must change with it — it is asserting the same watermark semantics.
  @list_sql """
  SELECT id FROM ops
  WHERE id > $1
    AND id < (
      SELECT COALESCE(
        MIN(id),
        (SELECT COALESCE(MAX(id), 0) + 1 FROM ops)
      )
      FROM ops
      WHERE xmin::text::xid8 >= pg_snapshot_xmin(pg_current_snapshot())
    )
  ORDER BY id ASC
  LIMIT 100
  """

  defp list_after(pid, cursor) do
    %Postgrex.Result{rows: rows} = Postgrex.query!(pid, @list_sql, [cursor])
    Enum.map(rows, fn [id] -> id end)
  end

  defp conn_opts do
    AnsibleRelay.Repo.config()
    |> Keyword.take([:username, :password, :hostname, :port, :database])
  end

  defp start_conn do
    {:ok, pid} = Postgrex.start_link(conn_opts())
    pid
  end

  defp insert_op(pid, tag) do
    %Postgrex.Result{rows: [[id]]} =
      Postgrex.query!(
        pid,
        """
        INSERT INTO ops
          (op_id, author_did, entity_type, entity_id, op_type, payload, signature,
           schema_version, received_at, inserted_at, updated_at)
        VALUES ($1,$2,'post','e','insert','p','s',1, now(), now(), now())
        RETURNING id
        """,
        ["gap-op-#{tag}-#{System.unique_integer([:positive])}", "did:test:gap"]
      )

    id
  end

  test "list/1 does not skip a committed-later row that holds a lower id" do
    holder = start_conn()
    committer = start_conn()
    reader = start_conn()

    on_exit(fn ->
      cleaner = start_conn()
      Postgrex.query!(cleaner, "DELETE FROM ops WHERE author_did = 'did:test:gap'", [])
      GenServer.stop(cleaner)
    end)

    # Baseline cursor: nothing of ours is visible yet.
    Postgrex.query!(reader, "DELETE FROM ops WHERE author_did = 'did:test:gap'", [])
    start_cursor = max_committed_id(reader)

    # Connection A opens a transaction and inserts a LOW-id row, but does NOT
    # commit — this reserves the lower bigserial id.
    Postgrex.query!(holder, "BEGIN", [])
    low_id = insert_op(holder, "low")

    # Connection B inserts + commits a HIGHER-id row (autocommit).
    high_id = insert_op(committer, "high")
    assert high_id > low_id

    # A reader must NOT serve the high row yet: the low id is still in flight, so
    # serving high_id would skip low_id forever once it commits.
    served_ids = list_after(reader, start_cursor)
    refute high_id in served_ids, "gap row #{high_id} served while #{low_id} uncommitted"

    # Now the low transaction commits. Both rows become servable in id order.
    Postgrex.query!(holder, "COMMIT", [])

    served_after_ids = list_after(reader, start_cursor)
    assert low_id in served_after_ids
    assert high_id in served_after_ids
    # low_id precedes high_id — the consumer sees the gap row, never skips it.
    assert Enum.find_index(served_after_ids, &(&1 == low_id)) <
             Enum.find_index(served_after_ids, &(&1 == high_id))

    Enum.each([holder, committer, reader], &GenServer.stop/1)
  end

  defp max_committed_id(pid) do
    %Postgrex.Result{rows: [[id]]} =
      Postgrex.query!(pid, "SELECT COALESCE(MAX(id), 0) FROM ops", [])

    id
  end
end
