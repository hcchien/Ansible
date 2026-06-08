defmodule AnsibleRelay.VpVerifierTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.{DidAccountCache, VpVerifier}

  @issuer_did "did:web:issuer.elix.cool"
  @holder_did "did:plc:abcdefghijklmnop"

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

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp holder_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp sign(priv_key, message) do
    :crypto.sign(:eddsa, :none, message, [priv_key, :ed25519])
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

  # Build a signed TrisAuraHumanityCredential VC.
  defp build_humanity_vc(holder_did, issuer_priv, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    valid_until = DateTime.add(DateTime.utc_now(), 90 * 86_400, :second) |> DateTime.to_iso8601()

    vc_without_proof = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://elix.cool/contexts/humanity/v1"
      ],
      "id" => Keyword.get(opts, :id, "https://issuer.elix.cool/vc/test001"),
      "type" => ["VerifiableCredential", "TrisAuraHumanityCredential"],
      "issuer" => Keyword.get(opts, :issuer, @issuer_did),
      "validFrom" => now,
      "validUntil" => Keyword.get(opts, :valid_until, valid_until),
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
  defp build_vp(holder_did, holder_priv, vcs, opts \\ []) do
    nonce = Keyword.get(opts, :nonce)
    audience = Keyword.get(opts, :audience)

    proof_options =
      %{
        "type" => "DataIntegrityProof",
        "cryptosuite" => "eddsa-jcs-2022",
        "verificationMethod" => "#{holder_did}#key-1",
        "created" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "proofPurpose" => "authentication"
      }
      |> then(fn p -> if nonce, do: Map.put(p, "challenge", nonce), else: p end)
      |> then(fn p -> if audience, do: Map.put(p, "domain", audience), else: p end)

    vp_with_options = %{
      "@context" => ["https://www.w3.org/ns/credentials/v2"],
      "type" => ["VerifiablePresentation"],
      "holder" => holder_did,
      "verifiableCredential" => vcs,
      "proof" => proof_options
    }

    proof_value = sign(holder_priv, canonical(vp_with_options))
    put_in(vp_with_options, ["proof", "proofValue"], proof_value)
  end

  # ─── Tests ───────────────────────────────────────────────────────────────────

  test "accepts valid TrisAuraHumanityCredential VP", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv, [vc])

    assert {:ok, "TrisAuraHumanityCredential"} = VpVerifier.verify(@holder_did, vp)
  end

  test "accepts VP with matching nonce and audience", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv, [vc], nonce: "nonce-123", audience: "https://relay.elix.cool")

    assert {:ok, "TrisAuraHumanityCredential"} =
             VpVerifier.verify(@holder_did, vp,
               nonce: "nonce-123",
               audience: "https://relay.elix.cool"
             )
  end

  test "rejects VP with wrong nonce", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv, [vc], nonce: "nonce-abc", audience: "https://relay.elix.cool")

    assert {:error, :wrong_nonce} =
             VpVerifier.verify(@holder_did, vp,
               nonce: "nonce-DIFFERENT",
               audience: "https://relay.elix.cool"
             )
  end

  test "rejects VP with wrong audience", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv, [vc], nonce: "nonce-123", audience: "https://evil.example")

    assert {:error, :wrong_audience} =
             VpVerifier.verify(@holder_did, vp,
               nonce: "nonce-123",
               audience: "https://relay.elix.cool"
             )
  end

  test "rejects VP with invalid holder signature", %{issuer_priv: issuer_priv} do
    {pub_hex, _priv} = holder_keypair()
    {_other_pub, other_priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, other_priv, [vc])

    assert {:error, :invalid_vp_proof} = VpVerifier.verify(@holder_did, vp)
  end

  test "rejects VP whose VC subject does not match holder", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc("did:plc:someoneelseabcd", issuer_priv)
    vp = build_vp(@holder_did, priv, [vc])

    assert {:error, :vc_subject_mismatch} = VpVerifier.verify(@holder_did, vp)
  end

  test "rejects expired VC (validUntil in the past)", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    past = DateTime.add(DateTime.utc_now(), -1, :second) |> DateTime.to_iso8601()
    vc = build_humanity_vc(@holder_did, issuer_priv, valid_until: past)
    vp = build_vp(@holder_did, priv, [vc])

    assert {:error, :vc_expired} = VpVerifier.verify(@holder_did, vp)
  end

  test "rejects VC with unknown credential type", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc =
      build_humanity_vc(@holder_did, issuer_priv)
      |> Map.put("type", ["VerifiableCredential", "UnknownType"])

    vp = build_vp(@holder_did, priv, [vc])

    assert {:error, :unknown_credential_type} = VpVerifier.verify(@holder_did, vp)
  end

  test "rejects VP when holder DID is not registered", %{issuer_priv: issuer_priv} do
    vc = build_humanity_vc(@holder_did, issuer_priv)
    {_pub, priv} = holder_keypair()
    vp = build_vp(@holder_did, priv, [vc])

    assert {:error, :holder_not_found} = VpVerifier.verify(@holder_did, vp)
  end

  test "rejects VC with untrusted issuer", %{issuer_priv: issuer_priv} do
    {pub_hex, priv} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.elix.cool")

    vc = build_humanity_vc(@holder_did, issuer_priv, issuer: "did:web:evil.example")
    vp = build_vp(@holder_did, priv, [vc])

    assert {:error, :invalid_vc_proof} = VpVerifier.verify(@holder_did, vp)
  end
end
