defmodule AnsibleAppview.Web.Router do
  use Plug.Router

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/health" do
    send_json(conn, 200, %{status: "ok", service: "ansible_appview", version: "0.1.0"})
  end

  post "/api/v1/timeline" do
    AnsibleAppview.Web.Controllers.TimelineController.timeline(conn, conn.body_params)
  end

  get "/api/v1/board-feed" do
    AnsibleAppview.Web.Controllers.TimelineController.board_feed(conn, conn.query_params)
  end

  get "/api/v1/home" do
    AnsibleAppview.Web.Controllers.TimelineController.home(conn, conn.query_params)
  end

  get "/api/v1/suggest/follows" do
    AnsibleAppview.Web.Controllers.DiscoveryController.suggest_follows(conn, conn.query_params)
  end

  get "/api/v1/explore" do
    AnsibleAppview.Web.Controllers.DiscoveryController.explore(conn, conn.query_params)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
