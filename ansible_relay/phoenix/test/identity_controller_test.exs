defmodule AnsibleRelay.Web.IdentityControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.IdentityCache
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp valid_anchor(did, challenge, public_key, private_key) do
    %{
      "did" => did,
      "zkp_proof" => "stub-proof",
      "zkp_circuit_version" => "passport_v1_dev",
      "verification_key_hash" => "sha256:dev-passport-v1-placeholder",
      "nullifier" => "nullifier_#{System.unique_integer()}",
      "public_key" => public_key,
      "challenge" => challenge,
      "challenge_signature" => sign(private_key, challenge)
    }
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    case IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "challenge endpoint issues a nonce for a DID" do
    did = "did:key:z6MkHttpChallenge#{System.unique_integer()}"

    response = post_json("/api/v1/identity/challenge", %{"did" => did})
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["did"] == did
    assert is_binary(body["challenge"])
    assert is_binary(body["expires_at"])
  end

  test "challenge endpoint validates required DID" do
    response = post_json("/api/v1/identity/challenge", %{})
    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "missing_required_fields"
    assert body["fields"] == ["did"]
  end

  test "anchor consumes a valid challenge and verifies DID" do
    did = "did:key:z6MkAnchor#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    challenge_response = post_json("/api/v1/identity/challenge", %{"did" => did})
    challenge = Jason.decode!(challenge_response.resp_body)["challenge"]

    response =
      post_json("/api/v1/identity/anchor", valid_anchor(did, challenge, public_key, private_key))

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["verified"] == true
    assert body["did"] == did
    assert IdentityCache.verified?(did)
  end

  test "anchor rejects development ZKP proof when dev proofs are disabled" do
    original = Application.get_env(:ansible_relay, :allow_dev_zkp_proofs, false)
    Application.put_env(:ansible_relay, :allow_dev_zkp_proofs, false)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :allow_dev_zkp_proofs, original)
    end)

    did = "did:key:z6MkNoDevProof#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    challenge_response = post_json("/api/v1/identity/challenge", %{"did" => did})
    challenge = Jason.decode!(challenge_response.resp_body)["challenge"]

    response =
      post_json("/api/v1/identity/anchor", valid_anchor(did, challenge, public_key, private_key))

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_zkp_proof"
  end

  test "anchor requires challenge fields" do
    did = "did:key:z6MkMissingChallenge#{System.unique_integer()}"

    response =
      post_json("/api/v1/identity/anchor", %{
        "did" => did,
        "zkp_proof" => "stub-proof",
        "zkp_circuit_version" => "passport_v1_dev",
        "verification_key_hash" => "sha256:dev-passport-v1-placeholder",
        "nullifier" => "nullifier_#{System.unique_integer()}",
        "public_key" => "abcdef0123456789"
      })

    assert response.status == 422

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "missing_required_fields"
    assert "challenge" in body["fields"]
    assert "challenge_signature" in body["fields"]
  end

  test "anchor rejects unsupported ZKP circuit version" do
    did = "did:key:z6MkBadCircuit#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    challenge_response = post_json("/api/v1/identity/challenge", %{"did" => did})
    challenge = Jason.decode!(challenge_response.resp_body)["challenge"]

    response =
      post_json(
        "/api/v1/identity/anchor",
        valid_anchor(did, challenge, public_key, private_key)
        |> Map.put("zkp_circuit_version", "passport_v999_unknown")
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "unsupported_zkp_circuit"
  end

  test "anchor rejects mismatched verification key hash" do
    did = "did:key:z6MkBadVkHash#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    challenge_response = post_json("/api/v1/identity/challenge", %{"did" => did})
    challenge = Jason.decode!(challenge_response.resp_body)["challenge"]

    response =
      post_json(
        "/api/v1/identity/anchor",
        valid_anchor(did, challenge, public_key, private_key)
        |> Map.put("verification_key_hash", "sha256:wrong-hash")
      )

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "verification_key_hash_mismatch"
  end

  test "anchor rejects a replayed challenge" do
    did = "did:key:z6MkReplay#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    challenge_response = post_json("/api/v1/identity/challenge", %{"did" => did})
    challenge = Jason.decode!(challenge_response.resp_body)["challenge"]

    first =
      post_json("/api/v1/identity/anchor", valid_anchor(did, challenge, public_key, private_key))

    assert first.status == 200

    second =
      post_json("/api/v1/identity/anchor", valid_anchor(did, challenge, public_key, private_key))

    assert second.status == 401
    assert Jason.decode!(second.resp_body)["error"] == "invalid_challenge"
  end

  test "anchor rejects expired challenge" do
    did = "did:key:z6MkExpiredHttpChallenge#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    past = DateTime.add(DateTime.utc_now(), -1, :second)
    {:ok, entry} = IdentityCache.issue_challenge(did, past)

    response =
      post_json(
        "/api/v1/identity/anchor",
        valid_anchor(did, entry.challenge, public_key, private_key)
      )

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "expired_challenge"
  end
end
