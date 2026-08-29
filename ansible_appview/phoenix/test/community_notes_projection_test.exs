defmodule AnsibleAppview.CommunityNotesProjectionTest do
  use ExUnit.Case, async: false
  use Plug.Test

  import Ecto.Query

  alias AnsibleAppview.Db.{ContextNote, FeedItem}
  alias AnsibleAppview.Ingest.Folder
  alias AnsibleAppview.Web.Router
  alias AnsibleAppview.{ContextNotes, Repo, SigningPayload, Timeline}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "folds a verified public note into its dedicated projection and API" do
    {pub, private_key} = keypair()

    target = signed_target_op(100, pub, private_key, "target-1")

    note =
      signed_op(
        101,
        pub,
        private_key,
        "insert",
        "community-note-1",
        note_payload("target-1", target)
      )

    assert Folder.apply_ops([target, note]) == {1, 101}

    projected = Repo.get!(ContextNote, "community-note-1")
    assert projected.target_entity_id == "target-1"
    assert projected.body == "Additional verified context"
    assert projected.signature == note["signature"]
    assert projected.deleted == false

    assert Repo.aggregate(from(f in FeedItem, where: f.entity_id == "community-note-1"), :count) ==
             0

    assert Timeline.for_authors([note["author_did"]], nil, 50).items == []

    response = get_json("/api/v1/context-notes?target_ref=target-1")
    assert response.status == 200
    decoded = Jason.decode!(response.resp_body)
    assert decoded["target"]["op_id"] == target["op_id"]
    assert decoded["target"]["content_hash"] == target_content_hash(target)
    assert [body] = decoded["notes"]
    assert body["note_id"] == "community-note-1"
    assert body["provenance"]["sig_verified"] == true
    assert body["provenance"]["source"] == "relay_firehose"
    refute Map.has_key?(body, "ratings")
    refute Map.has_key?(body, "rater_did")
  end

  test "rejects forged, private, and malformed context notes from public reads" do
    {pub, private_key} = keypair()
    target = signed_target_op(101, pub, private_key, "target-2")

    forged =
      signed_op(102, pub, private_key, "insert", "forged", note_payload("target-2", target))
      |> Map.put("signature", String.duplicate("0", 128))

    private =
      signed_op(
        103,
        pub,
        private_key,
        "insert",
        "private",
        Map.put(note_payload("target-2", target), "visibility", "unlisted")
      )

    malformed =
      signed_op(
        104,
        pub,
        private_key,
        "insert",
        "malformed",
        Map.put(note_payload("target-2", target), "sources", [])
      )

    assert Folder.apply_ops([target, forged, private, malformed]) == {1, 104}
    assert ContextNotes.for_target("target-2") == []
  end

  test "updates content without retargeting and delete withdraws the note" do
    {pub, private_key} = keypair()
    target = signed_target_op(103, pub, private_key, "target-3")
    other_target = signed_target_op(104, pub, private_key, "different-target")

    insert =
      signed_op(
        105,
        pub,
        private_key,
        "insert",
        "community-note-mutable",
        note_payload("target-3", target)
      )

    update =
      signed_op(
        106,
        pub,
        private_key,
        "update",
        "community-note-mutable",
        Map.put(note_payload("target-3", target), "body", "Corrected context")
      )

    retarget =
      signed_op(
        107,
        pub,
        private_key,
        "update",
        "community-note-mutable",
        note_payload("different-target", other_target)
      )

    assert Folder.apply_ops([target, other_target, insert, update, retarget]) == {2, 107}
    assert ContextNotes.get("community-note-mutable").body == "Corrected context"
    assert ContextNotes.get("community-note-mutable").target_entity_id == "target-3"

    delete =
      signed_op(108, pub, private_key, "delete", "community-note-mutable", %{
        "deletedAt" => "2026-08-30T00:00:00Z"
      })

    assert Folder.apply_ops([delete]) == {0, 108}
    assert ContextNotes.get("community-note-mutable") == nil
    assert Repo.get!(ContextNote, "community-note-mutable").deleted == true
  end

  test "API requires an explicit target and clamps its limit" do
    assert get_json("/api/v1/context-notes").status == 422
    assert get_json("/api/v1/context-notes?target_ref=missing&limit=10000").status == 200
  end

  test "does not project a note when the target revision hash is wrong" do
    {pub, private_key} = keypair()
    target = signed_target_op(110, pub, private_key, "target-hash")

    bad_note =
      signed_op(
        111,
        pub,
        private_key,
        "insert",
        "bad-target-hash",
        note_payload("target-hash", target)
        |> Map.put("targetContentHash", "sha256:" <> String.duplicate("f", 64))
      )

    assert Folder.apply_ops([target, bad_note]) == {1, 111}
    assert ContextNotes.for_target("target-hash") == []
  end

  test "orders target notes by revision log and enforces the requested limit" do
    {pub, private_key} = keypair()
    target = signed_target_op(120, pub, private_key, "target-order")

    older =
      signed_op(
        121,
        pub,
        private_key,
        "insert",
        "community-note-older",
        note_payload("target-order", target)
      )

    newer =
      signed_op(
        122,
        pub,
        private_key,
        "insert",
        "community-note-newer",
        note_payload("target-order", target)
      )

    assert Folder.apply_ops([target, older, newer]) == {1, 122}

    assert Enum.map(ContextNotes.for_target("target-order"), & &1.note_id) == [
             "community-note-newer",
             "community-note-older"
           ]

    response = get_json("/api/v1/context-notes?target_ref=target-order&limit=1")
    assert [%{"note_id" => "community-note-newer"}] = Jason.decode!(response.resp_body)["notes"]
  end

  defp keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp signed_op(log_id, public_key, private_key, op_type, entity_id, payload) do
    op = %{
      "log_id" => log_id,
      "op_id" => "op-#{log_id}",
      "author_did" => "did:key:community-author",
      "entity_type" => "context_note",
      "entity_id" => entity_id,
      "op_type" => op_type,
      "payload" => Base.encode64(Jason.encode!(payload)),
      "public_key_hex" => public_key,
      "reputation_tier" => "verified_human",
      "received_at" => "2026-08-30T00:00:00Z"
    }

    signature =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [private_key, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", signature)
  end

  defp signed_target_op(log_id, public_key, private_key, entity_id) do
    payload = %{"mode" => "murmur", "body" => "Target #{entity_id}", "visibility" => "public"}

    op = %{
      "log_id" => log_id,
      "op_id" => "target-op-#{log_id}",
      "author_did" => "did:key:target-author",
      "entity_type" => "murmur",
      "entity_id" => entity_id,
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(payload)),
      "public_key_hex" => public_key,
      "reputation_tier" => "verified_human",
      "received_at" => "2026-08-30T00:00:00Z"
    }

    signature =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [private_key, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", signature)
  end

  defp note_payload(target_ref, target) do
    %{
      "targetEntityType" => "murmur",
      "targetEntityId" => target_ref,
      "targetOpId" => target["op_id"],
      "targetContentHash" => target_content_hash(target),
      "body" => "Additional verified context",
      "sources" => [%{"url" => "https://example.test/evidence", "title" => "Evidence"}],
      "visibility" => "public",
      "createdAt" => "2026-08-30T00:00:00Z"
    }
  end

  defp target_content_hash(target) do
    payload = target["payload"] |> Base.decode64!() |> Jason.decode!()
    "sha256:" <> (:crypto.hash(:sha256, Jason.encode!(payload)) |> Base.encode16(case: :lower))
  end

  defp get_json(path), do: conn(:get, path) |> Router.call(@router_opts)
end
