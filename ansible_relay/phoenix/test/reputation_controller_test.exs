defmodule AnsibleRelay.Web.ReputationControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.DidAccountCache
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  @issuer_did "did:web:issuer.trisaura.io"
  @holder_did "did:plc:abcdefghijklmnop"

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp holder_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp sign(private_key, message) when is_binary(message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  # Recursively sort map keys alphabetically — mirrors Dart's _canonicalValue.
  defp deep_sort(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new(fn {k, v} -> {k, deep_sort(v)} end)
  end

  defp deep_sort(value) when is_list(value), do: Enum.map(value, &deep_sort/1)
  defp deep_sort(value), do: value

  defp canonical(value), do: value |> deep_sort() |> Jason.encode!()

  # Build a signed VC.
  defp build_vc(holder_did, issuer_priv, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    valid_until = DateTime.add(DateTime.utc_now(), 90 * 86_400, :second) |> DateTime.to_iso8601()
    credential_type = Keyword.get(opts, :credential_type, "TrisAuraHumanityCredential")

    vc_without_proof = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://trisaura.io/contexts/humanity/v1"
      ],
      "id" => "https://issuer.trisaura.io/vc/test001",
      "type" => ["VerifiableCredential", credential_type],
      "issuer" => @issuer_did,
      "validFrom" => now,
      "validUntil" => valid_until,
      "credentialSubject" => %{
        "id" => holder_did,
        "humanVerified" => true,
        "assuranceLevel" => "tw_natural_person_certificate",
        "assuranceMethod" => "tw_fido_or_moica",
        "jurisdiction" => "TW"
      }
    }

    proof_value = sign(issuer_priv, canonical(vc_without_proof))

    Map.put(vc_without_proof, "proof", %{
      "type" => "Ed25519Signature2020",
      "created" => now,
      "verificationMethod" => "#{@issuer_did}#key-1",
      "proofPurpose" => "assertionMethod",
      "proofValue" => proof_value
    })
  end

  # Build a signed VP using the canonical form:
  # sign(canonical(vp_with_proof_options_but_no_proof_value)).
  defp build_vp(holder_did, holder_priv_key, vcs) do
    proof_options = %{
      "type" => "DataIntegrityProof",
      "cryptosuite" => "eddsa-jcs-2022",
      "verificationMethod" => "#{holder_did}#key-1",
      "created" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "proofPurpose" => "authentication"
    }

    vp_with_options = %{
      "@context" => ["https://www.w3.org/ns/credentials/v2"],
      "type" => ["VerifiablePresentation"],
      "holder" => holder_did,
      "verifiableCredential" => vcs,
      "proof" => proof_options
    }

    proof_value = sign(holder_priv_key, canonical(vp_with_options))
    put_in(vp_with_options, ["proof", "proofValue"], proof_value)
  end

  setup do
    case DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    DidAccountCache.reset()

    # Generate issuer keypair using OTP so sign/verify use the same key format.
    {issuer_pub, issuer_priv} = :crypto.generate_key(:eddsa, :ed25519)
    issuer_pub_hex = Base.encode16(issuer_pub, case: :lower)

    Application.put_env(:ansible_relay, :trusted_vc_issuers, [
      %{did: @issuer_did, public_key_hex: issuer_pub_hex}
    ])

    {:ok, issuer_priv: issuer_priv}
  end

  test "present upgrades holder to verified_human with valid humanity credential VP",
       %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["reputation_tier"] == "verified_human"
    assert {:ok, %{reputation_tier: "verified_human"}} = DidAccountCache.get(@holder_did)
  end

  test "present does not treat email credential as verified human",
       %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv, credential_type: "EmailCredential")
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["reputation_tier"] == "basic"
    assert {:ok, %{reputation_tier: "basic"}} = DidAccountCache.get(@holder_did)
  end

  test "present rejects VP with invalid holder proof", %{issuer_priv: issuer_priv} do
    {pub_hex, _priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv)
    {_other_pub, other_priv} = holder_keypair()
    vp = build_vp(@holder_did, other_priv, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_vp"
  end

  test "present rejects VP when VC subject does not match holder", %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc("did:plc:someoneelse0001", issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status in [401, 422]
  end

  test "present does not downgrade a higher tier", %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()

    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io",
      reputation_tier: "verified_human"
    )

    vc = build_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    assert {:ok, %{reputation_tier: "verified_human"}} = DidAccountCache.get(@holder_did)
  end

  test "present returns 404 for unknown holder", %{issuer_priv: issuer_priv} do
    {_pub, priv_key} = holder_keypair()
    vc = build_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "holder_not_found"
  end
end
