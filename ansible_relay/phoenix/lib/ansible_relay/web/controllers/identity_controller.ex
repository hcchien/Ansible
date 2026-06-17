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
  alias AnsibleRelay.IdentityCache

  # GET /api/v1/identity/public-key/:did
  def public_key(conn, %{"did" => did}) do
    case IdentityCache.public_key_hex(did) do
      nil ->
        send_json(conn, 404, %{error: "did_not_found"})

      hex ->
        send_json(conn, 200, %{did: did, public_key_hex: hex})
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
