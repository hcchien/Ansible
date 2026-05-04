defmodule AnsibleRelay.Web.Plugs.VerifyDidAuth do
  @moduledoc """
  Plug for routes that require a verified DID in the request body.

  Usage in router:
      plug AnsibleRelay.Web.Plugs.VerifyDidAuth when action in [:ingest]

  Checks that `author_did` (from body_params) is present in the ETS
  identity cache and has not expired. Returns 401 if not.

  Note: In Q1 this is not wired into the router pipeline — the controllers
  perform the check inline. This plug exists for the Q2 Phoenix migration
  when controller pipelines replace the Plug.Router dispatch.
  """

  import Plug.Conn
  alias AnsibleRelay.IdentityCache

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    did = conn.body_params["author_did"]

    if did && IdentityCache.verified?(did) do
      assign(conn, :verified_did, did)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "unverified_did",
           message: "DID not anchored. Complete Phase 1 identity anchoring first."}))
      |> halt()
    end
  end
end
