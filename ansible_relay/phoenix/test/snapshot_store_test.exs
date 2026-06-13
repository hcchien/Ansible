defmodule AnsibleRelay.SnapshotStoreTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{Metrics, OpStore, Repo, SnapshotStore}
  alias AnsibleRelay.Db.Op

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for mod <- [OpStore, Metrics] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    # Retention defaults to :infinity from config; some tests opt in and restore.
    on_exit(fn ->
      Application.put_env(:ansible_relay, :snapshot_retention_days, :infinity)
    end)

    :ok
  end

  # --- Generation + verification ---

  test "generate produces a verifiable, relay-signed snapshot over seeded ops" do
    seed_ops(3)

    assert {:ok, snapshot} = SnapshotStore.generate()
    assert snapshot.op_count == 3
    assert snapshot.cursor > 0
    assert is_binary(snapshot.snapshot_cid)
    assert is_binary(snapshot.digest)
    assert is_binary(snapshot.signature)
    assert String.match?(snapshot.signing_public_key_hex, ~r/\A[0-9a-f]{64}\z/)

    # Signature + CID verify independently (no DB access in verify/1).
    assert SnapshotStore.verify(snapshot)
  end

  test "snapshot digest is recomputable from the covered op set" do
    seed_ops(4)
    assert {:ok, snapshot} = SnapshotStore.generate()

    # A consumer that folded these ops recomputes the same digest.
    ops = OpStore.list(after_log_id: 0, limit: 500)
    assert SnapshotStore.digest_for_ops(ops) == snapshot.digest
  end

  test "a tampered snapshot fails verification" do
    seed_ops(2)
    assert {:ok, snapshot} = SnapshotStore.generate()
    assert SnapshotStore.verify(snapshot)

    # Tamper with the digest (CID no longer matches body).
    assert refute_verify(%{snapshot | digest: flip_hex(snapshot.digest)})
    # Tamper with the cursor.
    assert refute_verify(%{snapshot | cursor: snapshot.cursor + 1})
    # Tamper with the signature.
    assert refute_verify(%{snapshot | signature: flip_hex(snapshot.signature)})
    # Tamper with the pinned public key.
    assert refute_verify(%{
             snapshot
             | signing_public_key_hex: flip_hex(snapshot.signing_public_key_hex)
           })
  end

  test "generate is idempotent by content (no duplicate at same cursor/state)" do
    seed_ops(2)
    assert {:ok, first} = SnapshotStore.generate()
    assert {:ok, second} = SnapshotStore.generate()
    assert first.snapshot_cid == second.snapshot_cid
    assert Repo.aggregate(AnsibleRelay.Db.OpSnapshot, :count, :id) == 1
  end

  test "latest and at_or_before return the right snapshots" do
    seed_ops(2)
    assert {:ok, snap1} = SnapshotStore.generate()
    seed_ops(2)
    assert {:ok, snap2} = SnapshotStore.generate()

    assert SnapshotStore.latest().snapshot_cid == snap2.snapshot_cid
    # Asking at/before snap1's cursor returns snap1, not the newer snap2.
    assert SnapshotStore.at_or_before(snap1.cursor).snapshot_cid == snap1.snapshot_cid
    # Below the first cursor: no snapshot.
    assert SnapshotStore.at_or_before(0) == nil
  end

  # --- Snapshot + delta reconstruct the full op set ---

  test "snapshot + delta together reconstruct the full op set" do
    seed_ops(3)
    assert {:ok, snapshot} = SnapshotStore.generate()
    # More ops arrive after the snapshot cursor.
    seed_ops(2)

    # Consumer: fold ops covered by the snapshot, then apply the delta after
    # the snapshot cursor. (log_ids are not contiguous from 1 across tests, so
    # partition the full log by the cursor rather than using cursor as a limit.)
    full = OpStore.list(after_log_id: 0, limit: 500)
    covered = Enum.filter(full, &(&1.log_id <= snapshot.cursor))
    delta = OpStore.list(after_log_id: snapshot.cursor, limit: 500)

    # The folded set matches the snapshot digest...
    assert SnapshotStore.digest_for_ops(covered) == snapshot.digest
    # ...and snapshot-covered + delta == the full op log.
    reconstructed = covered ++ delta
    assert Enum.map(reconstructed, & &1.op_id) == Enum.map(full, & &1.op_id)
    assert length(reconstructed) == 5
  end

  # --- Endpoint ---

  test "GET /api/v1/ops/snapshot returns the latest verifiable snapshot" do
    seed_ops(2)
    assert {:ok, _} = SnapshotStore.generate()

    conn = conn(:get, "/api/v1/ops/snapshot") |> Router.call(@router_opts)
    assert conn.status == 200

    %{"snapshot" => snap} = Jason.decode!(conn.resp_body)
    # Returned-over-HTTP snapshot (string keys) verifies independently.
    assert SnapshotStore.verify(snap)
    assert snap["op_count"] == 2
  end

  test "GET /api/v1/ops/snapshot returns 404 when no snapshot exists" do
    conn = conn(:get, "/api/v1/ops/snapshot") |> Router.call(@router_opts)
    assert conn.status == 404
    assert %{"error" => "no_snapshot_available"} = Jason.decode!(conn.resp_body)
  end

  test "GET /api/v1/ops/snapshot?cursor= returns the snapshot at/before the cursor" do
    seed_ops(2)
    assert {:ok, snap1} = SnapshotStore.generate()
    seed_ops(2)
    assert {:ok, _snap2} = SnapshotStore.generate()

    conn =
      conn(:get, "/api/v1/ops/snapshot?cursor=#{snap1.cursor}")
      |> Router.call(@router_opts)

    assert conn.status == 200
    %{"snapshot" => snap} = Jason.decode!(conn.resp_body)
    assert snap["snapshot_cid"] == snap1.snapshot_cid
  end

  # --- Retention / guarded prune ---

  test "prune is a no-op when retention is off (default)" do
    seed_ops(3)
    assert {:ok, _} = SnapshotStore.generate()
    assert SnapshotStore.prune() == {:noop, :retention_disabled}
    assert Repo.aggregate(Op, :count, :id) == 3
  end

  test "prune is a no-op when no snapshot has been published" do
    Application.put_env(:ansible_relay, :snapshot_retention_days, 1)
    seed_ops(2)
    assert SnapshotStore.prune() == {:noop, :no_snapshot}
    assert Repo.aggregate(Op, :count, :id) == 2
  end

  test "prune removes only snapshot-covered, aged, non-tombstone ops" do
    Application.put_env(:ansible_relay, :snapshot_retention_days, 7)

    # Old ops (older than the window): one insert (prunable) + one delete (tombstone).
    old = DateTime.add(DateTime.utc_now(), -30, :day)
    insert_op("old-insert", "insert", old)
    insert_op("old-tombstone", "delete", old)
    # A recent op inside the retention window (must NOT be pruned).
    insert_op("recent-insert", "insert", DateTime.utc_now())

    # Snapshot covers everything so far.
    assert {:ok, _snap} = SnapshotStore.generate()

    # An op that arrives AFTER the snapshot cursor — old but not snapshot-covered.
    insert_op("uncovered-old", "insert", old)

    assert {:ok, deleted} = SnapshotStore.prune()
    assert deleted == 1

    remaining = OpStore.list(after_log_id: 0, limit: 500) |> Enum.map(& &1.op_id)
    refute "old-insert" in remaining
    assert "old-tombstone" in remaining
    assert "recent-insert" in remaining
    assert "uncovered-old" in remaining
  end

  # --- Metrics ---

  test "generate emits the snapshot counter and cursor gauge" do
    seed_ops(2)
    assert {:ok, snapshot} = SnapshotStore.generate()

    body = Metrics.render()
    assert body =~ ~r/relay_snapshot_generated_total [1-9]/
    assert body =~ "relay_snapshot_cursor #{snapshot.cursor}"
  end

  # --- Helpers ---

  defp refute_verify(snapshot), do: not SnapshotStore.verify(snapshot)

  defp seed_ops(n) do
    for _ <- 1..n do
      insert_op("op-#{System.unique_integer([:positive])}", "insert", DateTime.utc_now())
    end
  end

  defp insert_op(op_id, op_type, received_at) do
    {:ok, _} =
      %Op{}
      |> Op.changeset(%{
        op_id: op_id,
        author_did: "did:key:zSnapshotTest",
        entity_type: "post",
        entity_id: "entity-#{System.unique_integer([:positive])}",
        op_type: op_type,
        payload: Base.encode64("body-#{op_id}"),
        signature: "deadbeef",
        received_at: received_at
      })
      |> Repo.insert()

    :ok
  end

  # Flip the first hex char so a digest/signature/key no longer matches.
  defp flip_hex(<<first::binary-size(1), rest::binary>>) do
    replacement = if first == "a", do: "b", else: "a"
    replacement <> rest
  end
end
