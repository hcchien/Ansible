defmodule AnsibleRelay.Web.Controllers.IdentityController do
  @moduledoc """
  Public-key lookup for a registered DID.

  The Phase 1 ZKP challenge/anchor flow this module used to host was retired in
  favour of `did:elix` + the self-certifying anchor (IdentityAnchorController)
  and the v2 passkeys registration (IdentityV2Controller). Only the public-key
  read survives — the app's relay client resolves a DID's verification key
  through it.
  """

  import Plug.Conn
  alias AnsibleRelay.{DidAccountCache, IdentityCache}

  # GET /api/v1/identity/public-key/:did
  def public_key(conn, %{"did" => did}) do
    case verification_key(did) do
      :not_found ->
        send_json(conn, 404, %{error: "did_not_found"})

      {:error, :unavailable} ->
        send_json(conn, 503, %{error: "verification_unavailable", retryable: true})

      {:ok, entry} ->
        send_json(conn, 200, %{
          did: did,
          public_key_hex: entry.public_key_hex,
          signing_algorithm: Map.get(entry, :signing_algorithm, "ed25519"),
          key_version: Map.get(entry, :key_version, 1)
        })
    end
  end

  # V2 account registration and hardware key rotation are authoritative in
  # DidAccountCache. IdentityCache remains as a legacy read path for older
  # anchors. Looking in the legacy cache first made otherwise healthy V2
  # accounts impossible to upgrade whenever verified_dids was unavailable.
  defp verification_key(did) do
    case DidAccountCache.get(did) do
      {:ok, entry} ->
        {:ok, entry}

      :not_found ->
        IdentityCache.get(did)

      {:error, :unavailable} ->
        case IdentityCache.get(did) do
          {:ok, entry} -> {:ok, entry}
          _ -> {:error, :unavailable}
        end
    end
  end

  # GET /api/v1/identity/handle/:did — resolve a DID to its registered handle so
  # clients can show a friendly author name instead of the raw DID.
  def handle(conn, %{"did" => did}) do
    case DidAccountCache.get(did) do
      {:ok, %{handle: handle}} when is_binary(handle) and handle != "" ->
        send_json(conn, 200, %{did: did, handle: handle})

      _ ->
        send_json(conn, 404, %{error: "handle_not_found"})
    end
  end

  # GET /api/v1/identity/attestation/:did — the issuer-signed VC that earned
  # this DID's reputation tier (portable re-verification layer). The VC is
  # served exactly as presented; the consumer re-verifies the issuer proof
  # against its own pinned issuer registry and must treat a missing/invalid
  # attestation as `basic` (fail closed).
  def attestation(conn, %{"did" => did}) do
    case AnsibleRelay.Identity.AttestationStore.get(did) do
      nil ->
        send_json(conn, 404, %{error: "attestation_not_found"})

      row ->
        send_json(conn, 200, %{
          did: row.did,
          credential_type: row.credential_type,
          reputation_tier: row.reputation_tier,
          vc: row.vc,
          presented_at: DateTime.to_iso8601(row.presented_at)
        })
    end
  end

  # GET /api/v1/identity/verify-handle?handle=&did= — DNS handle
  # verification (Phase 4.3). Read-only: reports whether the handle proves
  # control by the DID via DNS TXT or /.well-known. Rate-limited per peer —
  # each check triggers outbound DNS/HTTPS lookups.
  def verify_handle(conn, params) do
    handle = params["handle"]
    did = params["did"]

    cond do
      not is_binary(handle) or handle == "" or not is_binary(did) or did == "" ->
        send_json(conn, 422, %{error: "missing_handle_or_did"})

      match?(
        {:error, :rate_limited, _},
        AnsibleRelay.AbuseDetector.check_peer("verify_handle:" <> peer_hash(conn))
      ) ->
        send_json(conn, 429, %{error: "rate_limited"})

      true ->
        case AnsibleRelay.Identity.HandleVerifier.verify(handle, did) do
          {:ok, proof} ->
            send_json(conn, 200, %{verified: true, proof: to_string(proof)})

          {:error, :invalid_handle} ->
            send_json(conn, 422, %{error: "invalid_handle"})

          {:error, :not_verified} ->
            send_json(conn, 200, %{verified: false})
        end
    end
  end

  defp peer_hash(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
