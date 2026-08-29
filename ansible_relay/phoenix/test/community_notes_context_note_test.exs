defmodule AnsibleRelay.Web.CommunityNotesContextNoteTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{AbuseDetector, IdentityCache, OpStore}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    for mod <- [IdentityCache, AbuseDetector, OpStore, AnsibleRelay.DidAccountCache] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    AbuseDetector.reset()
    :ok
  end

  test "accepts a sourced public context note pinned to an exact target revision" do
    {did, private_key} = identity("Valid")
    target = insert_public_target(did, private_key)
    note = context_note(did, private_key, target)

    response = post_json("/api/v1/ops", note)

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
    assert OpStore.get_by_op_id(note["op_id"]).entity_type == "context_note"
  end

  test "rejects missing sources, malformed hashes, unsafe URLs, and non-public visibility" do
    {did, private_key} = identity("Shape")
    target = insert_public_target(did, private_key)

    invalid_payloads = [
      Map.put(note_payload(target), "sources", []),
      Map.put(note_payload(target), "targetContentHash", "sha256:nope"),
      Map.put(note_payload(target), "sources", [%{"url" => "file:///etc/passwd"}]),
      Map.put(note_payload(target), "visibility", "unlisted")
    ]

    Enum.each(invalid_payloads, fn payload ->
      response = post_json("/api/v1/ops", context_note(did, private_key, target, payload))
      assert response.status == 422

      assert Jason.decode!(response.resp_body)["error"] in [
               "invalid_context_note_payload",
               "private_content_not_relayable"
             ]
    end)
  end

  test "rejects a missing or mismatched target revision" do
    {did, private_key} = identity("Target")
    target = insert_public_target(did, private_key)

    missing = Map.put(note_payload(target), "targetOpId", "missing-op")
    response = post_json("/api/v1/ops", context_note(did, private_key, target, missing))
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "context_note_target_not_found"

    mismatch = Map.put(note_payload(target), "targetEntityId", "different-entity")
    response = post_json("/api/v1/ops", context_note(did, private_key, target, mismatch))
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "context_note_target_mismatch"
  end

  test "rejects a context note for a private or unlisted target" do
    {did, private_key} = identity("Private")

    target =
      build_op(did, private_key, "note", "private-target", "insert", %{
        "body" => "not public",
        "visibility" => "unlisted"
      })

    assert {:ok, _} = OpStore.append(to_store_op(target))

    response = post_json("/api/v1/ops", context_note(did, private_key, target))
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "context_note_target_not_public"
  end

  test "allows the note author to update without retargeting and to withdraw" do
    {did, private_key} = identity("Mutation")
    target = insert_public_target(did, private_key)
    insert = context_note(did, private_key, target)
    assert post_json("/api/v1/ops", insert).status == 202

    update_payload = Map.put(note_payload(target), "body", "Updated context")

    update =
      build_op(did, private_key, "context_note", insert["entity_id"], "update", update_payload)

    assert post_json("/api/v1/ops", update).status == 202

    delete =
      build_op(did, private_key, "context_note", insert["entity_id"], "delete", %{
        "deletedAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert post_json("/api/v1/ops", delete).status == 202
  end

  test "forbids retargeting and non-author mutation" do
    {alice, alice_private} = identity("Alice")
    {bob, bob_private} = identity("Bob")
    target = insert_public_target(alice, alice_private)
    insert = context_note(alice, alice_private, target)
    assert post_json("/api/v1/ops", insert).status == 202

    retarget_payload = Map.put(note_payload(target), "targetContentHash", valid_hash("b"))

    retarget =
      build_op(
        alice,
        alice_private,
        "context_note",
        insert["entity_id"],
        "update",
        retarget_payload
      )

    response = post_json("/api/v1/ops", retarget)
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "context_note_retarget_forbidden"

    foreign =
      build_op(
        bob,
        bob_private,
        "context_note",
        insert["entity_id"],
        "update",
        note_payload(target)
      )

    response = post_json("/api/v1/ops", foreign)
    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "not_original_author"
  end

  test "rejects a tampered context note signature" do
    {did, private_key} = identity("Signature")
    target = insert_public_target(did, private_key)

    note =
      context_note(did, private_key, target) |> Map.put("signature", String.duplicate("0", 128))

    response = post_json("/api/v1/ops", note)
    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  defp identity(suffix) do
    did = "did:key:z6MkContext#{suffix}#{System.unique_integer([:positive])}"
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    IdentityCache.put(did, Base.encode16(public_key, case: :lower), "context-nullifier-#{suffix}")
    {did, private_key}
  end

  defp insert_public_target(did, private_key) do
    target =
      build_op(
        did,
        private_key,
        "murmur",
        "target-#{System.unique_integer([:positive])}",
        "insert",
        %{
          "body" => "A public claim",
          "visibility" => "public",
          "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      )

    assert post_json("/api/v1/ops", target).status == 202
    target
  end

  defp context_note(did, private_key, target, payload \\ nil) do
    build_op(
      did,
      private_key,
      "context_note",
      "context-note-#{System.unique_integer([:positive])}",
      "insert",
      payload || note_payload(target)
    )
  end

  defp note_payload(target) do
    %{
      "targetEntityType" => target["entity_type"],
      "targetEntityId" => target["entity_id"],
      "targetOpId" => target["op_id"],
      "targetContentHash" => target_hash(target),
      "body" => "An official source provides additional context.",
      "sources" => [%{"url" => "https://example.test/source", "title" => "Source"}],
      "visibility" => "public",
      "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp valid_hash(char), do: "sha256:" <> String.duplicate(char, 64)

  defp target_hash(target) do
    {:ok, raw} = Base.decode64(target["payload"])
    payload = Jason.decode!(raw)
    "sha256:" <> (:crypto.hash(:sha256, canonical_json(payload)) |> Base.encode16(case: :lower))
  end

  defp build_op(did, private_key, entity_type, entity_id, op_type, payload) do
    op = %{
      "op_id" => "op-#{System.unique_integer([:positive])}",
      "author_did" => did,
      "entity_type" => entity_type,
      "entity_id" => entity_id,
      "op_type" => op_type,
      "payload" => Base.encode64(Jason.encode!(payload))
    }

    Map.put(op, "signature", sign(private_key, signing_payload(op)))
  end

  defp to_store_op(op) do
    %{
      op_id: op["op_id"],
      author_did: op["author_did"],
      entity_type: op["entity_type"],
      entity_id: op["entity_id"],
      op_type: op["op_type"],
      payload: op["payload"],
      signature: op["signature"],
      received_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp signing_payload(op) do
    %{
      "author_did" => op["author_did"],
      "entity_id" => op["entity_id"],
      "entity_type" => op["entity_type"],
      "op_id" => op["op_id"],
      "op_type" => op["op_type"],
      "payload" => op["payload"]
    }
    |> canonical_json()
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end
end
