defmodule AnsibleRelay.Web.ReputationControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.DidAccountCache
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  # RFC 8032 test vector 1 — same keys used in ansible_issuer dev config
  @issuer_private_key_hex "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae3d55"
  @issuer_public_key_hex "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  @issuer_did "did:web:issuer.trisaura.io"

  @holder_did "did:plc:abcdefghijklmnop"

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  # Generate a holder Ed25519 keypair
  defp holder_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  # Sign a binary with an Ed25519 private key; returns hex signature
  defp sign(private_key, message) when is_binary(message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  # Build a valid signed EmailCredential VC
  defp build_vc(holder_did) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    expiry = DateTime.add(DateTime.utc_now(), 90 * 86_400, :second) |> DateTime.to_iso8601()

    vc_without_proof = %{
      "@context" => ["https://www.w3.org/2018/credentials/v1"],
      "id" => "https://issuer.trisaura.io/vc/test001",
      "type" => ["VerifiableCredential", "EmailCredential"],
      "issuer" => @issuer_did,
      "issuanceDate" => now,
      "expirationDate" => expiry,
      "credentialSubject" => %{
        "id" => holder_did,
        "email" => "test@example.com",
        "emailVerified" => true
      }
    }

    {:ok, priv_bytes} = Base.decode16(@issuer_private_key_hex, case: :mixed)
    proof_value = sign(priv_bytes, Jason.encode!(vc_without_proof))

    Map.put(vc_without_proof, "proof", %{
      "type" => "Ed25519Signature2020",
      "created" => now,
      "verificationMethod" => "#{@issuer_did}#key-1",
      "proofPurpose" => "assertionMethod",
      "proofValue" => proof_value
    })
  end

  # Build a valid signed VP wrapping the given VCs
  defp build_vp(holder_did, holder_priv_key, vcs) do
    vp_without_proof = %{
      "@context" => ["https://www.w3.org/2018/credentials/v1"],
      "type" => ["VerifiablePresentation"],
      "holder" => holder_did,
      "verifiableCredential" => vcs
    }

    proof_value = sign(holder_priv_key, Jason.encode!(vp_without_proof))

    Map.put(vp_without_proof, "proof", %{
      "type" => "Ed25519Signature2020",
      "created" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "verificationMethod" => "#{holder_did}#key-1",
      "proofPurpose" => "authentication",
      "proofValue" => proof_value
    })
  end

  setup do
    case DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    DidAccountCache.reset()

    # Ensure Relay config includes the dev issuer key
    Application.put_env(:ansible_relay, :trusted_vc_issuers, [
      %{did: @issuer_did, public_key_hex: @issuer_public_key_hex}
    ])

    :ok
  end

  test "present upgrades holder to verified_human with valid VP" do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["reputation_tier"] == "verified_human"
    assert {:ok, %{reputation_tier: "verified_human"}} = DidAccountCache.get(@holder_did)
  end

  test "present rejects VP with invalid holder proof" do
    {pub_hex, _priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did)
    {_other_pub, other_priv} = holder_keypair()
    vp = build_vp(@holder_did, other_priv, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_vp"
  end

  test "present rejects VP when VC subject does not match holder" do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc("did:plc:someoneelse0001")
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status in [401, 422]
  end

  test "present does not downgrade a higher tier" do
    {pub_hex, priv_key} = holder_keypair()
    # Pre-set to verified_human
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io",
      reputation_tier: "verified_human"
    )

    vc = build_vc(@holder_did)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    # Still 200, tier unchanged
    assert response.status == 200
    assert {:ok, %{reputation_tier: "verified_human"}} = DidAccountCache.get(@holder_did)
  end

  test "present returns 404 for unknown holder" do
    {_pub, priv_key} = holder_keypair()
    vc = build_vc(@holder_did)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "holder_not_found"
  end
end
