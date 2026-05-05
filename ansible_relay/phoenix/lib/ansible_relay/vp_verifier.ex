defmodule AnsibleRelay.VpVerifier do
  @moduledoc """
  W3C Verifiable Presentation verifier for TrisAuraHumanityCredential.

  Verification order:
    1. VP holder — DID matches `holder` field; signature covers the VP with
       proof options (challenge, domain, type, etc.) but without proofValue,
       all keys sorted alphabetically to match the Dart canonical form.
    2. Challenge / audience — if opts[:nonce] or opts[:audience] are supplied,
       the corresponding proof fields must match exactly.
    3. Each embedded VC — issuer proof valid, subject matches holder, type
       recognised, not expired (checks `validUntil` then `expirationDate`).

  Proof format: Ed25519Signature2020 or DataIntegrityProof/eddsa-jcs-2022,
  proofValue = hex-encoded 64-byte Ed25519 signature.
  """

  alias AnsibleRelay.{DidAccountCache, SigVerifier}

  @recognised_credential_types ~w[TrisAuraHumanityCredential EmailCredential]

  @type error ::
          :holder_not_found
          | :invalid_vp_proof
          | :wrong_nonce
          | :wrong_audience
          | :no_credentials
          | :invalid_vc_proof
          | :vc_subject_mismatch
          | :vc_expired
          | :unknown_credential_type

  @doc """
  Verify a VP and return the credential type of the first accepted VC.

  Options:
    - `nonce:` — if set, the VP proof `challenge` field must match exactly
    - `audience:` — if set, the VP proof `domain` field must match exactly

  Returns `{:ok, credential_type}` or `{:error, reason}`.
  """
  @spec verify(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def verify(holder_did, vp, opts \\ []) when is_binary(holder_did) and is_map(vp) do
    with {:ok, pub_key_hex} <- resolve_holder_key(holder_did),
         :ok <- verify_vp_proof(vp, pub_key_hex, holder_did, opts),
         {:ok, vcs} <- extract_vcs(vp),
         {:ok, vc} <- pick_accepted_vc(vcs, holder_did) do
      {:ok, vc_credential_type(vc)}
    end
  end

  # --- Private ---

  defp resolve_holder_key(did) do
    case DidAccountCache.get(did) do
      {:ok, %{public_key_hex: pkh}} -> {:ok, pkh}
      _ -> {:error, :holder_not_found}
    end
  end

  defp verify_vp_proof(vp, pub_key_hex, expected_holder, opts) do
    proof = Map.get(vp, "proof", %{})
    proof_value = Map.get(proof, "proofValue", "")
    actual_holder = Map.get(vp, "holder", "")

    with :ok <- check_holder(actual_holder, expected_holder),
         :ok <- check_challenge(proof, opts[:nonce]),
         :ok <- check_domain(proof, opts[:audience]) do
      # Sign VP with proof options (minus proofValue), all keys sorted — must
      # match the canonical form produced by Dart's VpBuilder.canonicalPayload.
      proof_options = Map.delete(proof, "proofValue")
      canonical = vp |> Map.put("proof", proof_options) |> deep_sort_keys() |> Jason.encode!()

      if SigVerifier.verify_ed25519(pub_key_hex, canonical, proof_value) do
        :ok
      else
        {:error, :invalid_vp_proof}
      end
    end
  end

  defp check_holder(actual, expected) when actual == expected, do: :ok
  defp check_holder(_, _), do: {:error, :invalid_vp_proof}

  defp check_challenge(_proof, nil), do: :ok

  defp check_challenge(proof, expected) do
    if Map.get(proof, "challenge") == expected, do: :ok, else: {:error, :wrong_nonce}
  end

  defp check_domain(_proof, nil), do: :ok

  defp check_domain(proof, expected) do
    if Map.get(proof, "domain") == expected, do: :ok, else: {:error, :wrong_audience}
  end

  defp extract_vcs(%{"verifiableCredential" => [_ | _] = vcs}), do: {:ok, vcs}
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
    subject_id = vc |> Map.get("credentialSubject", %{}) |> Map.get("id")
    if subject_id == holder_did, do: :ok, else: {:error, :vc_subject_mismatch}
  end

  defp check_vc_type(vc) do
    types = Map.get(vc, "type", [])

    if Enum.any?(types, &(&1 in @recognised_credential_types)),
      do: :ok,
      else: {:error, :unknown_credential_type}
  end

  # Checks `validUntil` (W3C VC v2) then falls back to `expirationDate` (v1).
  defp check_vc_expiry(vc) do
    expiry_str = Map.get(vc, "validUntil") || Map.get(vc, "expirationDate")

    case expiry_str && DateTime.from_iso8601(expiry_str) do
      nil ->
        :ok

      {:ok, expiry, _} ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt,
          do: :ok,
          else: {:error, :vc_expired}

      _ ->
        :ok
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
        canonical = vc_without_proof |> deep_sort_keys() |> Jason.encode!()

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

  # Recursively sorts map keys alphabetically so Jason.encode! output matches
  # the canonical form produced by Dart's VpBuilder._canonicalValue.
  defp deep_sort_keys(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new(fn {k, v} -> {k, deep_sort_keys(v)} end)
  end

  defp deep_sort_keys(value) when is_list(value), do: Enum.map(value, &deep_sort_keys/1)
  defp deep_sort_keys(value), do: value
end
