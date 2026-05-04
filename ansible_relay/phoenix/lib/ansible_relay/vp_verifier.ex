defmodule AnsibleRelay.VpVerifier do
  @moduledoc """
  W3C Verifiable Presentation verifier.

  Verifies a VP submitted for reputation tier upgrade:

    1. VP holder proof
       - signature over canonical VP (without proof) JSON
       - verified against the holder's public key from DidAccountCache

    2. Each VC issuer proof
       - signature over canonical VC (without proof) JSON
       - verified against a trusted issuer public key from config

    3. Structural checks
       - VP holder == credentialSubject.id (proves the VC was issued TO this holder)
       - VC type includes a recognised credential type
       - VC not expired

  Proof format: Ed25519Signature2020, proofValue = hex-encoded 64-byte signature.

  TODO(P2): add challenge/response to VP proof to prevent replay attacks.
  """

  alias AnsibleRelay.{DidAccountCache, SigVerifier}

  @type error ::
          :holder_not_found
          | :invalid_vp_proof
          | :no_credentials
          | :invalid_vc_proof
          | :vc_subject_mismatch
          | :vc_expired
          | :unknown_credential_type

  @recognised_credential_types ~w[EmailCredential]

  @doc """
  Verify a VP and return the credential type of the first accepted VC.

  Returns `{:ok, credential_type}` or `{:error, reason}`.
  """
  @spec verify(String.t(), map()) :: {:ok, String.t()} | {:error, error()}
  def verify(holder_did, vp) when is_binary(holder_did) and is_map(vp) do
    with {:ok, pub_key_hex} <- resolve_holder_key(holder_did),
         :ok <- verify_vp_proof(vp, pub_key_hex, holder_did),
         {:ok, vcs} <- extract_vcs(vp),
         {:ok, vc} <- pick_accepted_vc(vcs, holder_did) do
      credential_type = vc_credential_type(vc)
      {:ok, credential_type}
    end
  end

  # --- Private ---

  defp resolve_holder_key(did) do
    case DidAccountCache.get(did) do
      {:ok, %{public_key_hex: pkh}} -> {:ok, pkh}
      _ -> {:error, :holder_not_found}
    end
  end

  defp verify_vp_proof(vp, pub_key_hex, expected_holder) do
    proof = Map.get(vp, "proof", %{})
    proof_value = Map.get(proof, "proofValue", "")

    actual_holder = Map.get(vp, "holder", "")

    if actual_holder != expected_holder do
      {:error, :invalid_vp_proof}
    else
      vp_without_proof = Map.delete(vp, "proof")
      canonical = Jason.encode!(vp_without_proof)

      if SigVerifier.verify_ed25519(pub_key_hex, canonical, proof_value) do
        :ok
      else
        {:error, :invalid_vp_proof}
      end
    end
  end

  defp extract_vcs(%{"verifiableCredential" => vcs}) when is_list(vcs) and length(vcs) > 0 do
    {:ok, vcs}
  end

  defp extract_vcs(_), do: {:error, :no_credentials}

  defp pick_accepted_vc(vcs, holder_did) do
    Enum.reduce_while(vcs, {:error, :no_credentials}, fn vc, _acc ->
      case validate_vc(vc, holder_did) do
        :ok -> {:halt, {:ok, vc}}
        {:error, _} = err -> {:cont, err}
      end
    end)
  end

  defp validate_vc(vc, holder_did) do
    with :ok <- check_vc_subject(vc, holder_did),
         :ok <- check_vc_type(vc),
         :ok <- check_vc_expiry(vc),
         :ok <- verify_vc_issuer_proof(vc) do
      :ok
    end
  end

  defp check_vc_subject(vc, holder_did) do
    subject_id =
      vc
      |> Map.get("credentialSubject", %{})
      |> Map.get("id")

    if subject_id == holder_did, do: :ok, else: {:error, :vc_subject_mismatch}
  end

  defp check_vc_type(vc) do
    types = Map.get(vc, "type", [])

    if Enum.any?(types, &(&1 in @recognised_credential_types)) do
      :ok
    else
      {:error, :unknown_credential_type}
    end
  end

  defp check_vc_expiry(vc) do
    case Map.get(vc, "expirationDate") do
      nil ->
        :ok

      date_str ->
        case DateTime.from_iso8601(date_str) do
          {:ok, expiry, _} ->
            if DateTime.compare(DateTime.utc_now(), expiry) == :lt,
              do: :ok,
              else: {:error, :vc_expired}

          _ ->
            :ok
        end
    end
  end

  defp verify_vc_issuer_proof(vc) do
    issuer_did = Map.get(vc, "issuer")
    proof = Map.get(vc, "proof", %{})
    proof_value = Map.get(proof, "proofValue", "")

    case find_trusted_issuer(issuer_did) do
      nil ->
        {:error, :invalid_vc_proof}

      %{public_key_hex: pub_key_hex} ->
        vc_without_proof = Map.delete(vc, "proof")
        canonical = Jason.encode!(vc_without_proof)

        if SigVerifier.verify_ed25519(pub_key_hex, canonical, proof_value),
          do: :ok,
          else: {:error, :invalid_vc_proof}
    end
  end

  defp find_trusted_issuer(issuer_did) when is_binary(issuer_did) do
    :ansible_relay
    |> Application.get_env(:trusted_vc_issuers, [])
    |> Enum.find(&(&1.did == issuer_did))
  end

  defp find_trusted_issuer(_), do: nil

  defp vc_credential_type(vc) do
    vc
    |> Map.get("type", [])
    |> Enum.find(&(&1 in @recognised_credential_types))
    |> Kernel.||("VerifiableCredential")
  end
end
