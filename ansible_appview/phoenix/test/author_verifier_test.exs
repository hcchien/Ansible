defmodule AnsibleAppview.AuthorVerifierTest do
  use ExUnit.Case, async: false
  alias AnsibleAppview.Ingest.{AuthorVerifier, Folder}
  alias AnsibleAppview.{Repo, Discovery, SigningPayload, DidElix}
  alias AnsibleAppview.Identity.{AnchorEncoding, ChainVerifier}

  defp fixture do
    op = File.read!(Path.join(__DIR__, "fixtures/web_author_proof_v1.json")) |> Jason.decode!()
    {op, op["payload"] |> Base.decode64!() |> Jason.decode!()}
  end

  defp encoded(op, payload),
    do: Map.put(op, "payload", payload |> Jason.encode!() |> Base.encode64())

  defp hex(bytes), do: Base.encode16(bytes, case: :lower)
  defp sign(key, data), do: :crypto.sign(:eddsa, :none, data, [key, :ed25519]) |> hex()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "real Relay enrollment and assertion independently verifies and folds" do
    {op, payload} = fixture()
    assert {:ok, _} = AuthorVerifier.verify(op, payload)
    assert ChainVerifier.verified_chain?(op["author_did"], op["identity_chain"])
    {:ok, _} = AnsibleAppview.Authority.Witness.checkpoint(op["author_did"], op["identity_chain"])
    {:ok, at, _} = DateTime.from_iso8601(payload["web_operation"]["created_at"])
    {:ok, _} = AnsibleAppview.Authority.Witness.observe(op, payload, at)
    assert {1, 707} = Folder.apply_ops([op])
    assert Enum.any?(Discovery.explore(nil, 30).items, &(&1.op_id == op["op_id"]))
  end

  test "receipt, booleans and claimed origin cannot substitute for an assertion" do
    {op, payload} = fixture()

    for key <-
          ~w(signature client_data_json authenticator_data delegation_signature registration_attestation) do
      modified = put_in(payload, ["web_author_proof", key], "AAAA")
      assert {:error, _} = AuthorVerifier.verify(encoded(op, modified), modified), key
    end

    modified =
      put_in(payload, ["web_author_proof", "delegation", "origin"], "https://evil.example")

    assert {:error, _} = AuthorVerifier.verify(encoded(op, modified), modified)

    modified =
      put_in(payload, ["web_author_proof", "delegation", "allowed_actions"], ["forum.read"])

    assert {:error, _} = AuthorVerifier.verify(encoded(op, modified), modified)
  end

  test "rejects payload substitution, arbitrary author, wrong authority and missing expiry" do
    {op, payload} = fixture()

    for field <- ~w(body title boardId threadId visibility federate createdAt) do
      changed = Map.put(payload, field, "forged")
      assert {:error, _} = AuthorVerifier.verify(encoded(op, changed), changed), field
    end

    assert {:error, _} =
             AuthorVerifier.verify(Map.put(op, "author_did", "did:elix:victim"), payload)

    assert {:error, _} = AuthorVerifier.verify(Map.put(op, "identity_chain", []), payload)

    assert {:error, :missing_anchor} =
             AuthorVerifier.verify(Map.delete(op, "anchor_expires_at"), payload)

    assert {:error, :expired_anchor} =
             AuthorVerifier.verify(
               Map.put(op, "anchor_expires_at", "2000-01-01T00:00:00Z"),
               payload
             )

    assert {0, 707} = Folder.apply_ops([encoded(op, Map.put(payload, "body", "forged"))])
    assert Discovery.explore(nil, 30).items == []
  end

  test "unverified canonical DID projection is ignored" do
    {op, payload} = fixture()
    forged = Map.put(op, "canonical_author_did", "did:elix:victim")
    bound = AuthorVerifier.bind_provenance(forged, payload)
    assert bound["canonical_author_did"] == op["author_did"]
    assert bound["public_key_hex"] == hd(op["identity_chain"])["identity_key"]
  end

  test "rotation preserves historical signatures but rejects use of an old key in a new epoch" do
    {pub, private} = :crypto.generate_key(:eddsa, :ed25519)
    {next_pub, next_private} = :crypto.generate_key(:eddsa, :ed25519)
    did = DidElix.derive(hex(pub), "rotation.elix.cool")

    genesis = %{
      "schema_version" => 3,
      "did" => did,
      "identity_key" => hex(pub),
      "identity_key_algorithm" => "ed25519",
      "handle" => "rotation.elix.cool",
      "custody_class" => "software",
      "devices" => [],
      "also_known_as" => [],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-01-01T00:00:00Z"
    }

    genesis = Map.put(genesis, "sig", sign(private, AnchorEncoding.canonical_body(genesis)))

    rotated =
      Map.merge(genesis, %{
        "identity_key" => hex(next_pub),
        "reason" => "rotation",
        "created_at" => "2026-02-01T00:00:00Z",
        "prev_anchor_cid" => AnchorEncoding.compute_cid(genesis)
      })

    body = AnchorEncoding.canonical_body(rotated)

    rotated =
      Map.merge(rotated, %{"sig" => sign(next_private, body), "device_sig" => sign(private, body)})

    chain = [genesis, rotated]
    assert ChainVerifier.verified_chain?(did, chain)

    base = %{
      "op_id" => "rotation-op",
      "author_did" => did,
      "entity_id" => "note",
      "entity_type" => "note",
      "op_type" => "insert",
      "identity_chain" => chain,
      "anchor_expires_at" => "2099-01-01T00:00:00Z"
    }

    for {at, key, expected} <- [
          {"2026-01-15T00:00:00Z", private, :ok},
          {"2026-03-01T00:00:00Z", next_private, :ok},
          {"2026-03-01T00:00:00Z", private, :error}
        ] do
      payload = %{"body" => "history", "createdAt" => at, "visibility" => "public"}
      op = encoded(base, payload)
      op = Map.put(op, "signature", sign(key, SigningPayload.build(op)))
      assert elem(AuthorVerifier.verify(op, payload), 0) == expected

      if expected == :ok do
        provenance = AuthorVerifier.bind_provenance(op, payload)

        assert provenance["public_key_hex"] ==
                 if(key == private, do: hex(pub), else: hex(next_pub))
      end
    end
  end
end
