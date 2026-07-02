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
    case IdentityCache.public_key_hex(did) do
      nil ->
        send_json(conn, 404, %{error: "did_not_found"})

      hex ->
        send_json(conn, 200, %{did: did, public_key_hex: hex})
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

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
