defmodule AnsibleIssuer.VcIssuer do
  @moduledoc """
  Builds and signs W3C Verifiable Credentials (EmailCredential type).

  Credential structure:
    @context: W3C credentials v1 + Tris-Aura context
    type:     ["VerifiableCredential", "EmailCredential"]
    proof:    Ed25519Signature2020

  Signing canonical form:
    Jason.encode!(vc_without_proof)  →  Ed25519 signature  →  hex proofValue

  TODO(P2): encode proofValue as multibase base58btc per W3C Ed25519Signature2020 spec.
  """

  @vc_context [
    "https://www.w3.org/2018/credentials/v1",
    "https://trisaura.io/credentials/v1"
  ]

  @doc """
  Issue a signed EmailCredential VC for (holder_did, email).
  Returns the full VC as a map (ready for Jason.encode!/1).
  """
  def issue_email_vc(holder_did, email) when is_binary(holder_did) and is_binary(email) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    ttl_days = Application.get_env(:ansible_issuer, :vc_ttl_days, 90)
    expiry = DateTime.add(DateTime.utc_now(), ttl_days * 86_400, :second) |> DateTime.to_iso8601()

    issuer_did = Application.get_env(:ansible_issuer, :issuer_did)
    issuer_url = Application.get_env(:ansible_issuer, :issuer_service_url)
    vc_id = "#{issuer_url}/vc/#{random_id()}"

    vc_without_proof = %{
      "@context" => @vc_context,
      "id" => vc_id,
      "type" => ["VerifiableCredential", "EmailCredential"],
      "issuer" => issuer_did,
      "issuanceDate" => now,
      "expirationDate" => expiry,
      "credentialSubject" => %{
        "id" => holder_did,
        "email" => email,
        "emailVerified" => true
      }
    }

    proof_value = sign_canonical(vc_without_proof)

    Map.put(vc_without_proof, "proof", %{
      "type" => "Ed25519Signature2020",
      "created" => now,
      "verificationMethod" => "#{issuer_did}#key-1",
      "proofPurpose" => "assertionMethod",
      "proofValue" => proof_value
    })
  end

  @doc """
  Verify a VC's issuer proof signature.
  Returns true if the signature is valid, false otherwise.
  """
  def verify_vc_proof(%{"proof" => proof} = vc) do
    proof_value = Map.get(proof, "proofValue", "")
    vc_without_proof = Map.delete(vc, "proof")
    canonical = Jason.encode!(vc_without_proof)

    issuer_pub_hex = Application.get_env(:ansible_issuer, :issuer_public_key_hex)
    verify_ed25519(issuer_pub_hex, canonical, proof_value)
  end

  def verify_vc_proof(_), do: false

  @doc """
  Verify a VC proof given an explicit issuer public key hex.
  Used by external verifiers (e.g. the Relay) that don't share this app's config.
  """
  def verify_vc_proof_with_key(%{"proof" => proof} = vc, issuer_pub_hex)
      when is_binary(issuer_pub_hex) do
    proof_value = Map.get(proof, "proofValue", "")
    vc_without_proof = Map.delete(vc, "proof")
    canonical = Jason.encode!(vc_without_proof)
    verify_ed25519(issuer_pub_hex, canonical, proof_value)
  end

  def verify_vc_proof_with_key(_, _), do: false

  # --- Private ---

  defp sign_canonical(map) do
    canonical = Jason.encode!(map)
    priv_hex = Application.get_env(:ansible_issuer, :issuer_private_key_hex)

    with {:ok, priv_bytes} <- Base.decode16(priv_hex, case: :mixed) do
      sig = :crypto.sign(:eddsa, :none, canonical, [priv_bytes, :ed25519])
      Base.encode16(sig, case: :lower)
    else
      _ -> raise "Invalid issuer private key hex in config"
    end
  end

  defp verify_ed25519(pub_hex, message, sig_hex) do
    with {:ok, pub_bytes} <- Base.decode16(pub_hex, case: :mixed),
         {:ok, sig_bytes} <- Base.decode16(sig_hex, case: :mixed) do
      :crypto.verify(:eddsa, :none, message, sig_bytes, [pub_bytes, :ed25519])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp random_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
