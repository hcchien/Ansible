defmodule AnsibleRelay.Web.XrpcControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{AbuseDetector, DidAccountCache, OpStore}

  @router_opts Router.init([])

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp get_json(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  defp ed25519_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  # Seed a DID into DidAccountCache with a real Ed25519 public key hex
  defp seed_did(did, pub_hex, handle \\ nil) do
    h = handle || "#{System.unique_integer([:positive])}.trisaura.io"
    DidAccountCache.put(did, pub_hex, h)
  end

  # Build a valid createRecord body signed with the given private key
  defp valid_create_record(did, pub_hex, priv_key) do
    record = %{
      "$type" => "app.bsky.feed.post",
      "text" => "hello",
      "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    record_json = Jason.encode!(record)
    sig = sign(priv_key, record_json)
    seed_did(did, pub_hex)

    %{
      "repo" => did,
      "collection" => "app.bsky.feed.post",
      "record" => record,
      "commit_sig" => sig
    }
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    for mod <- [DidAccountCache, AbuseDetector, OpStore] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    DidAccountCache.reset()
    AbuseDetector.reset()
    :ok
  end

  # ---- POST /xrpc/com.atproto.repo.createRecord ----

  test "returns 200 with uri and cid for a valid signed record" do
    {pub_hex, priv_key} = ed25519_keypair()
    did = "did:plc:xrpcrec#{System.unique_integer([:positive])}"
    body = valid_create_record(did, pub_hex, priv_key)

    response = post_json("/xrpc/com.atproto.repo.createRecord", body)

    assert response.status == 200
    resp = Jason.decode!(response.resp_body)
    assert String.starts_with?(resp["uri"], "at://#{did}/app.bsky.feed.post/")
    assert String.starts_with?(resp["cid"], "bafyreistub")
  end

  test "returns 401 for unknown / unregistered DID" do
    {pub_hex, priv_key} = ed25519_keypair()
    did = "did:plc:unknown#{System.unique_integer([:positive])}"
    # Build record but do NOT seed the DID into cache
    record = %{"$type" => "app.bsky.feed.post", "text" => "ghost"}
    record_json = Jason.encode!(record)
    sig = sign(priv_key, record_json)

    body = %{
      "repo" => did,
      "collection" => "app.bsky.feed.post",
      "record" => record,
      "commit_sig" => sig
    }

    response = post_json("/xrpc/com.atproto.repo.createRecord", body)

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "unregistered_did"
  end

  test "returns 401 for tampered signature" do
    {pub_hex, priv_key} = ed25519_keypair()
    did = "did:plc:badsig#{System.unique_integer([:positive])}"
    record = %{"$type" => "app.bsky.feed.post", "text" => "tampered"}
    record_json = Jason.encode!(record)
    # Sign wrong message so signature is invalid
    bad_sig = sign(priv_key, record_json <> "tamper")
    seed_did(did, pub_hex)

    body = %{
      "repo" => did,
      "collection" => "app.bsky.feed.post",
      "record" => record,
      "commit_sig" => bad_sig
    }

    response = post_json("/xrpc/com.atproto.repo.createRecord", body)

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_sig"
  end

  test "returns 422 when required fields are missing" do
    response = post_json("/xrpc/com.atproto.repo.createRecord", %{"repo" => "did:plc:foo"})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "missing_fields"
  end

  test "rate-limited DID receives 429 after token bucket exhaustion" do
    previous = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 1, refill_per_second: 0, suspension_ms: 5_000},
      peer: %{capacity: 20, refill_per_second: 20, suspension_ms: 60_000}
    })

    AbuseDetector.reset()

    try do
      {pub_hex, priv_key} = ed25519_keypair()
      did = "did:plc:ratelim#{System.unique_integer([:positive])}"

      # Build and register DID once (seed_did is idempotent)
      seed_did(did, pub_hex)

      make_record = fn ->
        record = %{
          "$type" => "app.bsky.feed.post",
          "text" => "burst",
          "ts" => System.unique_integer()
        }

        record_json = Jason.encode!(record)
        sig = sign(priv_key, record_json)

        post_json("/xrpc/com.atproto.repo.createRecord", %{
          "repo" => did,
          "collection" => "app.bsky.feed.post",
          "record" => record,
          "commit_sig" => sig
        })
      end

      first = make_record.()
      assert first.status == 200

      second = make_record.()
      assert second.status == 429

      body = Jason.decode!(second.resp_body)
      assert body["error"] == "rate_limited"
      assert body["detail"]["reason"] == "did_rate_limited"
      assert body["detail"]["retry_after_ms"] > 0
    after
      AbuseDetector.reset()

      if is_nil(previous),
        do: Application.delete_env(:ansible_relay, :abuse_detector),
        else: Application.put_env(:ansible_relay, :abuse_detector, previous)
    end
  end

  test "rate limit is per-DID — a different DID is unaffected" do
    previous = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 1, refill_per_second: 0, suspension_ms: 5_000},
      peer: %{capacity: 20, refill_per_second: 20, suspension_ms: 60_000}
    })

    AbuseDetector.reset()

    try do
      {pub1_hex, priv1} = ed25519_keypair()
      {pub2_hex, priv2} = ed25519_keypair()
      did1 = "did:plc:rldid1#{System.unique_integer([:positive])}"
      did2 = "did:plc:rldid2#{System.unique_integer([:positive])}"

      seed_did(did1, pub1_hex)
      seed_did(did2, pub2_hex)

      make_record = fn did, pub_hex, priv ->
        record = %{
          "$type" => "app.bsky.feed.post",
          "text" => "x",
          "ts" => System.unique_integer()
        }

        record_json = Jason.encode!(record)
        sig = sign(priv, record_json)
        seed_did(did, pub_hex)

        post_json("/xrpc/com.atproto.repo.createRecord", %{
          "repo" => did,
          "collection" => "app.bsky.feed.post",
          "record" => record,
          "commit_sig" => sig
        })
      end

      # Exhaust did1
      assert make_record.(did1, pub1_hex, priv1).status == 200
      assert make_record.(did1, pub1_hex, priv1).status == 429

      # did2 is unaffected
      assert make_record.(did2, pub2_hex, priv2).status == 200
    after
      AbuseDetector.reset()

      if is_nil(previous),
        do: Application.delete_env(:ansible_relay, :abuse_detector),
        else: Application.put_env(:ansible_relay, :abuse_detector, previous)
    end
  end

  # ---- GET /xrpc/com.atproto.identity.resolveHandle ----

  test "resolveHandle returns DID for a registered handle" do
    {pub_hex, _} = ed25519_keypair()
    did = "did:plc:resolveme#{System.unique_integer([:positive])}"
    handle = "alice#{System.unique_integer([:positive])}.trisaura.io"
    DidAccountCache.put(did, pub_hex, handle)

    response = get_json("/xrpc/com.atproto.identity.resolveHandle?handle=#{handle}")

    assert response.status == 200
    assert Jason.decode!(response.resp_body)["did"] == did
  end

  test "resolveHandle returns 404 for unknown handle" do
    response = get_json("/xrpc/com.atproto.identity.resolveHandle?handle=nobody.trisaura.io")

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "handle_not_found"
  end

  test "resolveHandle returns 422 when handle param is missing" do
    response = get_json("/xrpc/com.atproto.identity.resolveHandle")

    assert response.status == 422
  end
end
