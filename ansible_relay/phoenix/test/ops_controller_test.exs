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

    Map.put(op, "signature", sign(private_key, op["op_id"] <> op["payload"]))
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    # Ensure GenServers are running
    for mod <- [IdentityCache, AbuseDetector, OpStore] do
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

  # ---- GET /api/v1/ops/delta ----

  test "delta returns 200 with ops, next_cursor, has_more" do
    did = "did:key:z6MkDelta#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    # Insert a couple of ops
    post_json("/api/v1/ops", valid_op(did, private_key))
    post_json("/api/v1/ops", valid_op(did, private_key))

    response = get_json("/api/v1/ops/delta?cursor=0&limit=100")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert is_list(body["ops"])
    assert is_integer(body["next_cursor"])
    assert is_boolean(body["has_more"])
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
