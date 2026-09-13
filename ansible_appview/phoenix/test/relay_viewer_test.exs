defmodule AnsibleAppview.RelayViewerTest do
  use ExUnit.Case, async: false
  alias AnsibleAppview.{Repo, DidElix, SigningPayload}
  alias AnsibleAppview.Authority.Witness
  alias AnsibleAppview.Identity.AnchorEncoding
  alias AnsibleAppview.Ingest.{AuthorVerifier, Folder}
  defp hex(x), do: Base.encode16(x, case: :lower)
  defp sign(key, bytes), do: :crypto.sign(:eddsa, :none, bytes, [key, :ed25519]) |> hex()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {pub, private} = :crypto.generate_key(:eddsa, :ed25519)
    {next, next_private} = :crypto.generate_key(:eddsa, :ed25519)
    did = DidElix.derive(hex(pub), "witness.elix.cool")

    initial = %{
      "schema_version" => 3,
      "did" => did,
      "identity_key" => hex(pub),
      "identity_key_algorithm" => "ed25519",
      "handle" => "witness.elix.cool",
      "custody_class" => "software",
      "devices" => [],
      "also_known_as" => [],
      "reason" => "initial",
      "prev_anchor_cid" => nil,
      "created_at" => "2026-01-01T00:00:00Z"
    }

    initial = Map.put(initial, "sig", sign(private, AnchorEncoding.canonical_body(initial)))

    rotated =
      Map.merge(initial, %{
        "identity_key" => hex(next),
        "reason" => "rotation",
        "prev_anchor_cid" => AnchorEncoding.compute_cid(initial),
        "created_at" => "2026-02-01T00:00:00Z"
      })

    body = AnchorEncoding.canonical_body(rotated)

    rotated =
      Map.merge(rotated, %{"sig" => sign(next_private, body), "device_sig" => sign(private, body)})

    %{did: did, private: private, next_private: next_private, initial: initial, rotated: rotated}
  end

  defp operation(c, id, key, at \\ "2026-01-15T00:00:00Z") do
    payload = %{"body" => "original #{id}", "createdAt" => at, "visibility" => "public"}

    op = %{
      "log_id" => System.unique_integer([:positive]),
      "op_id" => id,
      "author_did" => c.did,
      "entity_type" => "murmur",
      "entity_id" => id,
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(payload)),
      "identity_chain" => [c.initial],
      "anchor_expires_at" => "2099-01-01T00:00:00Z"
    }

    {Map.put(op, "signature", sign(key, SigningPayload.build(op))), payload}
  end

  defp relay_op(op, chain \\ nil, received \\ "2026-01-15T00:00:00Z") do
    op
    |> Map.put("identity_chain", chain || op["identity_chain"])
    |> Map.put("received_at", received)
    |> Map.put("authority_status", %{
      "version" => 1,
      "did" => op["author_did"],
      "state" => "active",
      "checked_at" => DateTime.to_iso8601(DateTime.utc_now())
    })
  end

  test "independent Viewer bootstrap and rebuild need no author checkpoint", c do
    {op, payload} = operation(c, "bootstrap", c.private)
    op = relay_op(op)
    assert {1, _} = Folder.apply_ops([op], authority_source: :relay)
    assert {:ok, bound} = Witness.observe_relay(op, payload)
    assert bound["observation_kind"] == "relay_state_checked"
    # Simulate a separate Viewer with no observations or enrollments.
    Repo.query!("TRUNCATE feed_items, authority_observations, authority_frontiers")
    assert {1, _} = Folder.apply_ops([op], authority_source: :relay)
  end

  test "receipt time permits historical keys but rejects backdated new content", c do
    {old, payload} = operation(c, "old-receipt", c.private)
    chain = [c.initial, c.rotated]
    assert {:ok, _} = Witness.observe_relay(relay_op(old, chain), payload)
    {attack, body} = operation(c, "backdated", c.private)

    assert {:error, :unobserved_obsolete_authority} =
             Witness.observe_relay(relay_op(attack, chain, "2026-03-01T00:00:00Z"), body)

    {rollback, body} = operation(c, "rollback", c.private)
    assert {:error, :authority_rollback_or_fork} = Witness.observe_relay(relay_op(rollback), body)
  end

  test "tampered bytes and missing status do not become signed", c do
    {op, payload} = operation(c, "tampered", c.private)
    assert {:error, :relay_authority_unavailable} = Witness.observe_relay(op, payload)

    assert {:error, :bad_signature} =
             Witness.observe_relay(relay_op(Map.put(op, "signature", "00")), payload)

    assert Repo.query!("SELECT 1 FROM authority_observations WHERE did=$1", [c.did]).rows == []
  end

  test "old pending records automatically retry exact bytes with fresh evidence", c do
    {op, _payload} = operation(c, "pending-proof", c.private)
    assert {0, _} = Folder.apply_ops([op])

    fetch = fn _base, cursor, limit ->
      assert cursor == op["log_id"] - 1
      assert limit == 1
      {:ok, %{ops: [relay_op(op)]}}
    end

    assert 1 == AnsibleAppview.Authority.Pending.retry_due("https://relay.example", fetch)
    assert Repo.query!("SELECT 1 FROM authority_pending WHERE did=$1", [c.did]).rows == []

    assert 0 ==
             AnsibleAppview.Authority.Pending.retry_due("https://relay.example", fn _, _, _ ->
               flunk("already retired")
             end)
  end

  test "retry mismatches and transient failures preserve durable pending work", c do
    {op, _} = operation(c, "retry-failure", c.private)
    assert {0, _} = Folder.apply_ops([op])
    fetch = fn _, _, _ -> {:ok, %{ops: [relay_op(Map.put(op, "signature", "changed"))]}} end
    assert 0 == AnsibleAppview.Authority.Pending.retry_due("https://relay.example", fetch)

    assert [[1]] =
             Repo.query!("SELECT attempts FROM authority_pending WHERE op_id=$1", [op["op_id"]]).rows

    assert 0 ==
             AnsibleAppview.Authority.Pending.retry_due("https://relay.example", fn _, _, _ ->
               flunk("backoff")
             end)

    Repo.query!("UPDATE authority_pending SET next_retry_at=$1", [
      DateTime.add(DateTime.utc_now(), -60)
    ])

    assert 0 ==
             AnsibleAppview.Authority.Pending.retry_due("https://relay.example", fn _, _, _ ->
               {:error, :offline}
             end)

    assert [[2]] =
             Repo.query!("SELECT attempts FROM authority_pending WHERE op_id=$1", [op["op_id"]]).rows
  end

  test "Relay revocation permits prior receipts but rejects later or rolled-back active status" do
    op =
      File.read!(Path.join(__DIR__, "fixtures/witness_author_proof_v1.json")) |> Jason.decode!()

    payload = op["payload"] |> Base.decode64!() |> Jason.decode!()
    at = payload["web_operation"]["created_at"]
    {:ok, receipt, _} = DateTime.from_iso8601(at)
    hash = payload["web_author_proof"]["delegation"]["credential_id_hash"]
    op = relay_op(op, nil, at)

    op =
      put_in(op, ["authority_status", "credential"], %{
        "credential_hash" => hash,
        "state" => "revoked",
        "revoked_at" => DateTime.to_iso8601(DateTime.add(receipt, 1))
      })

    assert {:ok, _} = Witness.observe_relay(op, payload)
    Repo.query!("DELETE FROM authority_observations WHERE did=$1", [op["author_did"]])
    later = Map.put(op, "received_at", DateTime.to_iso8601(DateTime.add(receipt, 2)))
    assert {:error, :delegation_not_current} = Witness.observe_relay(later, payload)

    rollback =
      put_in(later, ["authority_status", "credential"], %{
        "credential_hash" => hash,
        "state" => "active"
      })

    assert {:error, :delegation_not_current} = Witness.observe_relay(rollback, payload)
  end

  test "late superseded replay cannot resurrect a deleted projection", c do
    {op, _} = operation(c, "deleted-history", c.private)
    op = relay_op(op)
    assert {1, _} = Folder.apply_ops([op], authority_source: :relay)
    Repo.query!("UPDATE feed_items SET deleted=true WHERE op_id=$1", [op["op_id"]])
    old = put_in(op, ["authority_status", "superseded"], true)
    assert {0, _} = Folder.apply_ops([old], authority_source: :relay)

    assert [[true]] =
             Repo.query!("SELECT deleted FROM feed_items WHERE op_id=$1", [op["op_id"]]).rows
  end
end
