defmodule AnsibleRelay.Web.OpsControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{AbuseDetector, IdentityCache, OpStore}

  @router_opts Router.init([])

  # Helper to build a POST conn with a JSON body
  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  # Helper to build a GET conn with query params
  defp get_json(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  # Seed a verified DID into the ETS cache directly
  defp seed_did(did, public_key \\ "pubkey_hex_test") do
    IdentityCache.put(did, public_key, "nullifier_#{System.unique_integer()}")
  end

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
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

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  # Build a valid op body (all required fields present)
  defp valid_op(did, private_key) do
    op = %{
      "op_id" => "op-#{System.unique_integer()}",
      "author_did" => did,
      "entity_type" => "post",
      "entity_id" => "entity-#{System.unique_integer()}",
      "op_type" => "insert",
      "payload" => Base.encode64("hello world")
    }

    Map.put(op, "signature", sign(private_key, signing_payload(op)))
  end

  # Build a murmur/note op whose payload is base64(JSON), matching the app's
  # CrdtOpBuilder encoding convention.
  defp content_op(did, private_key, entity_type, payload_map) do
    op = %{
      "op_id" => "op-#{System.unique_integer()}",
      "author_did" => did,
      "entity_type" => entity_type,
      "entity_id" => "entity-#{System.unique_integer()}",
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(payload_map))
    }

    Map.put(op, "signature", sign(private_key, signing_payload(op)))
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    # Ensure GenServers are running
    for mod <- [IdentityCache, AbuseDetector, OpStore, AnsibleRelay.DidAccountCache] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    AbuseDetector.reset()
    :ok
  end

  # ---- POST /api/v1/ops ----

  test "verified DID can ingest a valid op and gets 202" do
    did = "did:key:z6MkIngest#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response = post_json("/api/v1/ops", valid_op(did, private_key))
    assert response.status == 202

    body = Jason.decode!(response.resp_body)
    assert body["accepted"] == true
    assert is_integer(body["log_id"])
  end

  test "legacy identity cannot write when the first-party policy is P-256 only" do
    original = Application.get_env(:ansible_relay, :identity_write_algorithms)
    Application.put_env(:ansible_relay, :identity_write_algorithms, ["p256-sha256"])

    on_exit(fn ->
      Application.put_env(:ansible_relay, :identity_write_algorithms, original)
    end)

    did = "did:key:z6MkLegacyWrite#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response = post_json("/api/v1/ops", valid_op(did, private_key))

    assert response.status == 409
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "identity_key_upgrade_required"
    assert body["expected"] == ["p256-sha256"]
  end

  test "sync writes require a WebAuthn capability when enforcement is enabled" do
    original =
      Application.get_env(:ansible_relay, :webauthn_sync_capability_required, false)

    Application.put_env(:ansible_relay, :webauthn_sync_capability_required, true)

    on_exit(fn ->
      Application.put_env(
        :ansible_relay,
        :webauthn_sync_capability_required,
        original
      )
    end)

    did = "did:key:z6MkCapability#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response = post_json("/api/v1/ops", valid_op(did, private_key))

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_sync_capability"
  end

  test "unverified DID gets 401" do
    did = "did:key:z6MkNoAnchor#{System.unique_integer()}"
    {_public_key, private_key} = ed25519_keypair()
    response = post_json("/api/v1/ops", valid_op(did, private_key))
    assert response.status == 401

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "unverified_did"
  end

  test "duplicate op_id gets 409" do
    did = "did:key:z6MkDupOp#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = valid_op(did, private_key)
    first = post_json("/api/v1/ops", op)
    assert first.status == 202

    second = post_json("/api/v1/ops", op)
    assert second.status == 409

    body = Jason.decode!(second.resp_body)
    assert body["error"] == "duplicate_op_id"
  end

  test "a JSON-object payload returns 422 (not a 500) since the store expects a string" do
    did = "did:key:z6MkMapPayload#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    # A map payload passes validation and signature (canonical_json handles maps)
    # but the store's payload column is a string, so the changeset cast fails.
    # The controller must translate that to a 422, not raise CaseClauseError → 500.
    op = %{
      "op_id" => "op-#{System.unique_integer()}",
      "author_did" => did,
      "entity_type" => "post",
      "entity_id" => "entity-#{System.unique_integer()}",
      "op_type" => "insert",
      "payload" => %{"body" => "a map, not a string"}
    }

    op = Map.put(op, "signature", sign(private_key, signing_payload(op)))

    response = post_json("/api/v1/ops", op)
    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "invalid_op_payload"
  end

  test "missing required fields returns 422" do
    did = "did:key:z6MkMissing#{System.unique_integer()}"
    seed_did(did)

    incomplete = %{"author_did" => did, "op_type" => "insert"}
    response = post_json("/api/v1/ops", incomplete)
    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "missing_required_fields"
    assert is_list(body["fields"])
  end

  test "invalid entity_type returns 422" do
    did = "did:key:z6MkBadEntity#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = valid_op(did, private_key) |> Map.put("entity_type", "spaceship")
    response = post_json("/api/v1/ops", op)
    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "invalid_value"
    assert body["field"] == "entity_type"
  end

  test "invalid op_type returns 422" do
    did = "did:key:z6MkBadOpType#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = valid_op(did, private_key) |> Map.put("op_type", "explode")
    response = post_json("/api/v1/ops", op)
    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "invalid_value"
    assert body["field"] == "op_type"
  end

  test "DID exceeding local rate limit gets 429" do
    previous = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 1, refill_per_second: 0, suspension_ms: 1_000},
      peer: %{capacity: 20, refill_per_second: 20, suspension_ms: 60_000}
    })

    AbuseDetector.reset()

    try do
      did = "did:key:z6MkRateLimited#{System.unique_integer()}"
      {public_key, private_key} = ed25519_keypair()
      seed_did(did, public_key)

      first = post_json("/api/v1/ops", valid_op(did, private_key))
      assert first.status == 202

      second = post_json("/api/v1/ops", valid_op(did, private_key))
      assert second.status == 429

      body = Jason.decode!(second.resp_body)
      assert body["error"] == "rate_limited"
      assert body["detail"]["reason"] == "did_rate_limited"
      assert body["detail"]["retry_after_ms"] > 0
    after
      AbuseDetector.reset()

      if is_nil(previous) do
        Application.delete_env(:ansible_relay, :abuse_detector)
      else
        Application.put_env(:ansible_relay, :abuse_detector, previous)
      end
    end
  end

  test "verified DID can ingest a public murmur op and gets 202" do
    did = "did:key:z6MkMurmur#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = content_op(did, private_key, "murmur", %{"text" => "hello", "visibility" => "public"})
    response = post_json("/api/v1/ops", op)
    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
  end

  test "murmur op without a visibility field is accepted (murmur has no visibility)" do
    did = "did:key:z6MkMurmurNoVis#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = content_op(did, private_key, "murmur", %{"text" => "hello"})
    response = post_json("/api/v1/ops", op)
    assert response.status == 202
  end

  test "verified DID can ingest a public note op and gets 202" do
    did = "did:key:z6MkNote#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = content_op(did, private_key, "note", %{"body" => "essay", "visibility" => "unlisted"})
    response = post_json("/api/v1/ops", op)
    assert response.status == 202
  end

  test "private note op is rejected with 422 private_content_not_relayable" do
    did = "did:key:z6MkNotePriv#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = content_op(did, private_key, "note", %{"body" => "secret", "visibility" => "private"})
    response = post_json("/api/v1/ops", op)
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "private_content_not_relayable"
  end

  test "note op missing visibility is rejected" do
    did = "did:key:z6MkNoteNoVis#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = content_op(did, private_key, "note", %{"body" => "essay"})
    response = post_json("/api/v1/ops", op)
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "private_content_not_relayable"
  end

  test "verified DID can ingest a follow op and gets 202" do
    did = "did:key:z6MkFollow#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op =
      content_op(did, private_key, "follow", %{
        "targetDid" => "did:key:z6MkAlice",
        "visibility" => "federated"
      })

    response = post_json("/api/v1/ops", op)
    assert response.status == 202
  end

  test "verified DID can ingest a profile op and gets 202" do
    did = "did:key:z6MkProfile#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op =
      content_op(did, private_key, "profile", %{
        "handle" => "alice.example",
        "displayName" => "Alice",
        "bio" => "hello",
        "visibility" => "public"
      })

    response = post_json("/api/v1/ops", op)
    assert response.status == 202
  end

  # ---- Posting gate (posting_policy["min_post_tier"]) ----

  defp insert_hosted_board(posting_policy) do
    board_id = "gated-board-#{System.unique_integer([:positive])}"

    AnsibleRelay.Repo.insert!(%AnsibleRelay.Db.ForumHostBoard{
      hosted_board_id: board_id,
      slug: board_id,
      canonical_board_uri: "http://localhost:4001/boards/#{board_id}",
      title: "Board #{board_id}",
      posting_policy: posting_policy
    })

    board_id
  end

  defp seed_reputation_tier(did, tier) do
    :ok =
      AnsibleRelay.DidAccountCache.put(
        did,
        "pubkey_hex_tier_test",
        "tier_handle_#{System.unique_integer([:positive])}",
        reputation_tier: tier
      )
  end

  test "thread insert into a tier-gated board rejects a basic DID with the 403 contract" do
    did = "did:key:z6MkGatedBasic#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    op = content_op(did, private_key, "thread", %{"boardId" => board_id, "title" => "Hi"})
    response = post_json("/api/v1/ops", op)

    assert response.status == 403

    assert Jason.decode!(response.resp_body) == %{
             "error" => "posting_requires_tier",
             "required_tier" => "verified_human",
             "current_tier" => "basic"
           }
  end

  test "composite local board id cannot bypass a hosted board posting policy" do
    did = "did:key:z6MkCompositeBasic#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    op =
      content_op(did, private_key, "thread", %{
        "boardId" => "relay-node_#{board_id}",
        "title" => "Must still be gated"
      })

    response = post_json("/api/v1/ops", op)

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "posting_requires_tier"
  end

  test "post insert (reply) into a tier-gated board is gated by the same key" do
    did = "did:key:z6MkGatedReply#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    op =
      content_op(did, private_key, "post", %{
        "boardId" => board_id,
        "threadId" => "thread-1",
        "body" => "reply"
      })

    response = post_json("/api/v1/ops", op)

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "posting_requires_tier"
  end

  test "thread insert into a tier-gated board accepts a verified_human DID" do
    did = "did:key:z6MkGatedHuman#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    seed_reputation_tier(did, "verified_human")
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    op = content_op(did, private_key, "thread", %{"boardId" => board_id, "title" => "Hi"})
    response = post_json("/api/v1/ops", op)

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
  end

  test "thread insert into an ungated board stays unchanged for a basic DID" do
    did = "did:key:z6MkUngated#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    board_id = insert_hosted_board(%{"min_trust_tier" => "self_custody_did"})

    op = content_op(did, private_key, "thread", %{"boardId" => board_id, "title" => "Hi"})
    response = post_json("/api/v1/ops", op)

    assert response.status == 202
  end

  test "thread update op on a gated board is not gated (gate applies to creation only)" do
    did = "did:key:z6MkGatedUpdate#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    insert =
      content_op(did, private_key, "thread", %{"boardId" => board_id, "title" => "Original"})

    assert post_json("/api/v1/ops", insert).status == 202

    op = %{
      "op_id" => "op-#{System.unique_integer()}",
      "author_did" => did,
      "entity_type" => "thread",
      "entity_id" => insert["entity_id"],
      "op_type" => "update",
      "payload" => Base.encode64(Jason.encode!(%{"boardId" => board_id, "title" => "Edited"}))
    }

    op = Map.put(op, "signature", sign(private_key, signing_payload(op)))
    response = post_json("/api/v1/ops", op)

    assert response.status == 202
  end

  test "only the original author can update or delete a post" do
    alice = "did:key:z6MkOwner#{System.unique_integer()}"
    bob = "did:key:z6MkOther#{System.unique_integer()}"
    {alice_public, alice_private} = ed25519_keypair()
    {bob_public, bob_private} = ed25519_keypair()
    seed_did(alice, alice_public)
    seed_did(bob, bob_public)

    insert = content_op(alice, alice_private, "post", %{"content" => "original"})
    assert post_json("/api/v1/ops", insert).status == 202

    for op_type <- ["update", "delete"] do
      mutation = %{
        "op_id" => "op-#{System.unique_integer()}",
        "author_did" => bob,
        "entity_type" => "post",
        "entity_id" => insert["entity_id"],
        "op_type" => op_type,
        "payload" => Base.encode64(Jason.encode!(%{"content" => "not yours"}))
      }

      mutation = Map.put(mutation, "signature", sign(bob_private, signing_payload(mutation)))
      response = post_json("/api/v1/ops", mutation)

      assert response.status == 403
      assert Jason.decode!(response.resp_body)["error"] == "not_original_author"
    end
  end

  test "author mutation compare-and-swap rejects a stale revision" do
    did = "did:key:z6MkRevision#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    insert = content_op(did, private_key, "post", %{"content" => "original"})
    assert post_json("/api/v1/ops", insert).status == 202

    update = %{
      op_id: "web-update-#{System.unique_integer()}",
      author_did: did,
      entity_type: "post",
      entity_id: insert["entity_id"],
      op_type: "update",
      payload: Base.encode64(Jason.encode!(%{"content" => "updated"})),
      signature: "test"
    }

    assert {:ok, _} = OpStore.append_author_mutation(update, insert["op_id"])

    assert {:error, :revision_conflict} =
             OpStore.append_author_mutation(
               %{update | op_id: "web-delete-#{System.unique_integer()}", op_type: "delete"},
               insert["op_id"]
             )
  end

  test "thread insert referencing a board not hosted here passes through" do
    did = "did:key:z6MkForeignBoard#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op =
      content_op(did, private_key, "thread", %{
        "boardId" => "board-not-hosted-#{System.unique_integer([:positive])}",
        "title" => "Hi"
      })

    response = post_json("/api/v1/ops", op)
    assert response.status == 202
  end

  # ---- GET /api/v1/ops/delta ----

  test "delta returns 200 with ops, next_cursor, has_more" do
    did = "did:key:z6MkDelta#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    base_response = get_json("/api/v1/ops/delta?cursor=0&limit=1000")
    base_cursor = Jason.decode!(base_response.resp_body)["next_cursor"]

    # Insert a couple of ops
    post_json("/api/v1/ops", valid_op(did, private_key))
    post_json("/api/v1/ops", valid_op(did, private_key))

    response = get_json("/api/v1/ops/delta?cursor=#{base_cursor}&limit=100")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert is_list(body["ops"])
    assert is_integer(body["next_cursor"])
    assert is_boolean(body["has_more"])
    assert Enum.all?(body["ops"], &is_binary(&1["public_key_hex"]))
    assert Enum.all?(body["ops"], &(&1["public_key_hex"] == public_key))
    # Each op carries the author's reputation tier (default "basic").
    assert Enum.all?(body["ops"], &is_binary(&1["reputation_tier"]))
    assert Enum.all?(body["ops"], &(&1["reputation_tier"] == "basic"))
  end

  test "delta with cursor filters older ops" do
    did = "did:key:z6MkCursor#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    r1 = post_json("/api/v1/ops", valid_op(did, private_key))
    log_id_1 = Jason.decode!(r1.resp_body)["log_id"]

    _r2 = post_json("/api/v1/ops", valid_op(did, private_key))

    # Fetch ops after the first log_id — should include only the second op
    response = get_json("/api/v1/ops/delta?cursor=#{log_id_1}&limit=100")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert length(body["ops"]) >= 1

    Enum.each(body["ops"], fn op ->
      assert op["log_id"] > log_id_1
    end)
  end

  test "delta respects limit and reports has_more" do
    did = "did:key:z6MkLimited#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    # Record a high enough cursor so only fresh ops matter
    base_response = get_json("/api/v1/ops/delta?cursor=0&limit=1000")
    base_cursor = Jason.decode!(base_response.resp_body)["next_cursor"]

    # Insert 3 fresh ops
    Enum.each(1..3, fn _ -> post_json("/api/v1/ops", valid_op(did, private_key)) end)

    response = get_json("/api/v1/ops/delta?cursor=#{base_cursor}&limit=2")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert length(body["ops"]) == 2
    assert body["has_more"] == true
  end

  # ---- Op schema_version (Phase 0 — API versioning) ----

  # schema_version is intentionally outside the signing payload, so a signed
  # op stays valid whether or not the field is present.
  test "op without schema_version is accepted and served as version 1" do
    did = "did:key:z6MkSchemaDefault#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response = post_json("/api/v1/ops", valid_op(did, private_key))
    assert response.status == 202
    log_id = Jason.decode!(response.resp_body)["log_id"]

    delta = get_json("/api/v1/ops/delta?cursor=#{log_id - 1}&limit=1")
    assert delta.status == 200

    [op] = Jason.decode!(delta.resp_body)["ops"]
    assert op["log_id"] == log_id
    assert op["schema_version"] == 1
  end

  test "op with explicit schema_version 1 round-trips through delta" do
    did = "did:key:z6MkSchemaOne#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    op = valid_op(did, private_key) |> Map.put("schema_version", 1)
    response = post_json("/api/v1/ops", op)
    assert response.status == 202
    log_id = Jason.decode!(response.resp_body)["log_id"]

    delta = get_json("/api/v1/ops/delta?cursor=#{log_id - 1}&limit=1")
    [served] = Jason.decode!(delta.resp_body)["ops"]
    assert served["schema_version"] == 1
  end

  test "schema_version above the relay's current version is rejected with 422" do
    did = "did:key:z6MkSchemaFuture#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    future = AnsibleRelay.Protocol.current_version() + 1
    op = valid_op(did, private_key) |> Map.put("schema_version", future)
    response = post_json("/api/v1/ops", op)
    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "invalid_schema_version"
    assert body["value"] == future
    assert body["max_supported"] == AnsibleRelay.Protocol.current_version()
  end

  test "non-integer or sub-1 schema_version is rejected with 422" do
    did = "did:key:z6MkSchemaBad#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    for bad <- ["1", 0, -3] do
      op = valid_op(did, private_key) |> Map.put("schema_version", bad)
      response = post_json("/api/v1/ops", op)
      assert response.status == 422
      assert Jason.decode!(response.resp_body)["error"] == "invalid_schema_version"
    end
  end

  # ---- GET /health ----

  test "health endpoint returns 200" do
    response = get_json("/health")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["status"] == "ok"
    assert body["relay"] == "ansible_relay"
  end

  test "unknown route returns 404" do
    response = get_json("/api/v1/does_not_exist")
    assert response.status == 404

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "not_found"
  end
end
