defmodule AnsibleRelay.Web.Controllers.ReputationController do
  @moduledoc """
  POST /api/v2/reputation/present — submit a W3C VP to upgrade reputation tier.

  Flow:
    1. Validate request fields (holder_did, vp)
    2. Verify VP via VpVerifier (holder proof + VC issuer proof + structural checks).
       If `nostr_binding` is present, also verify the short-lived Nostr
       binding event before assigning local Nostr pubkey trust.
    3. Map credential type → reputation tier
    4. Update DID entry in DidAccountCache (and write-through to PostgreSQL)
    5. Return {did, reputation_tier}

  Tier mapping:
    TrisAuraHumanityCredential → "verified_human"
    EmailCredential → "basic"
  """

  alias AnsibleRelay.{DidAccountCache, VpVerifier}

  @tier_for_credential %{
    "TrisAuraHumanityCredential" => "verified_human",
    "EmailCredential" => "basic"
  }

  def present(conn, params) do
    with {:ok, holder_did} <- require_field(params, "holder_did"),
         {:ok, vp} <- require_map(params, "vp"),
         :ok <- validate_did(holder_did) do
      case verify_presentation(holder_did, vp, Map.get(params, "nostr_binding")) do
        {:ok, credential_type, nostr_pubkey} ->
          tier = Map.get(@tier_for_credential, credential_type, "basic")
          upgrade_tier(conn, holder_did, tier, nostr_pubkey)

        {:error, :holder_not_found} ->
          send_json(conn, 404, %{error: "holder_not_found"})

        {:error, :invalid_vp_proof} ->
          send_json(conn, 401, %{error: "invalid_vp"})

        {:error, :no_credentials} ->
          send_json(conn, 422, %{error: "no_credentials"})

        {:error, :invalid_vc_proof} ->
          send_json(conn, 401, %{error: "invalid_vc"})

        {:error, :vc_subject_mismatch} ->
          send_json(conn, 422, %{error: "vc_subject_mismatch"})

        {:error, :vc_expired} ->
          send_json(conn, 422, %{error: "vc_expired"})

        {:error, :unknown_credential_type} ->
          send_json(conn, 422, %{error: "unsupported_credential_type"})

        {:error, :invalid_nostr_binding} ->
          send_json(conn, 401, %{error: "invalid_nostr_binding"})

        {:error, :nostr_binding_mismatch} ->
          send_json(conn, 422, %{error: "nostr_binding_mismatch"})

        {:error, :nostr_binding_expired} ->
          send_json(conn, 401, %{error: "nostr_binding_expired"})
      end
    else
      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_field", field: field})

      {:error, :not_a_map, field} ->
        send_json(conn, 422, %{error: "invalid_field", field: field})

      {:error, :invalid_did} ->
        send_json(conn, 422, %{error: "invalid_did"})
    end
  end

  # --- Helpers ---

  defp verify_presentation(holder_did, vp, nil) do
    with {:ok, credential_type} <- VpVerifier.verify(holder_did, vp) do
      {:ok, credential_type, nil}
    end
  end

  defp verify_presentation(holder_did, vp, nostr_binding) when is_map(nostr_binding) do
    VpVerifier.verify_nostr_binding(holder_did, vp, nostr_binding)
  end

  defp verify_presentation(_holder_did, _vp, _nostr_binding),
    do: {:error, :invalid_nostr_binding}

  defp upgrade_tier(conn, holder_did, tier, nostr_pubkey) do
    case DidAccountCache.get(holder_did) do
      {:ok, entry} ->
        if tier_rank(tier) > tier_rank(entry.reputation_tier) do
          :ok =
            DidAccountCache.put(
              holder_did,
              entry.public_key_hex,
              entry.handle,
              reputation_tier: tier
            )
        end

        body = %{did: holder_did, reputation_tier: tier}

        body =
          if nostr_pubkey do
            :ok = DidAccountCache.put_nostr_binding(nostr_pubkey, holder_did, tier)
            Map.put(body, :nostr_pubkey, nostr_pubkey)
          else
            body
          end

        send_json(conn, 200, body)

      :not_found ->
        send_json(conn, 404, %{error: "holder_not_found"})
    end
  end

  # Higher rank = higher trust. Prevents downgrade attacks.
  defp tier_rank("verified_human"), do: 3
  defp tier_rank("dns_verified"), do: 2
  defp tier_rank("basic"), do: 1
  defp tier_rank(_), do: 0

  defp require_field(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_field, key}}
      "" -> {:error, {:missing_field, key}}
      val -> {:ok, val}
    end
  end

  defp require_map(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_field, key}}
      val when is_map(val) -> {:ok, val}
      _ -> {:error, :not_a_map, key}
    end
  end

  defp validate_did(did) when is_binary(did) do
    if Regex.match?(~r/\Adid:(plc:[a-z2-7]{10,}|web:.+)\z/, did),
      do: :ok,
      else: {:error, :invalid_did}
  end

  defp validate_did(_), do: {:error, :invalid_did}

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
