defmodule AnsibleIssuer.Web.Router do
  use Plug.Router
  require Logger

  plug Plug.Logger
  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :dispatch

  get "/health" do
    issuer_did = Application.get_env(:ansible_issuer, :issuer_did)
    mock_mode = Application.get_env(:ansible_issuer, :mock_mode, true)

    send_json(conn, 200, %{
      status: "ok",
      service: "ansible_issuer",
      issuer_did: issuer_did,
      mock_mode: mock_mode
    })
  end

  # VC issuance
  post "/api/v1/vc/request" do
    AnsibleIssuer.Web.Controllers.VcController.request_vc(conn, conn.body_params)
  end

  post "/api/v1/vc/issue" do
    AnsibleIssuer.Web.Controllers.VcController.issue_vc(conn, conn.body_params)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
