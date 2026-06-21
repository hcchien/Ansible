defmodule AnsibleAppview.Web.Router do
  use Plug.Router

  plug(AnsibleAppview.Web.Plugs.RequireProtocolVersion)
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

  # Phase 0 — Observability baseline (G17): Prometheus metrics scrape target.
  # Deliberately outside /api/* so the protocol-version plug never gates it.
  get "/metrics" do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, AnsibleAppview.Metrics.render())
  end

  # Phase 0 — API versioning: advertise the protocol versions this AppView
  # speaks so clients can detect upgrade requirements before they break.
  get "/api/v1/meta" do
    send_json(conn, 200, %{
      service: "ansible_appview",
      version: "0.1.0",
      protocol: AnsibleAppview.Protocol.advertisement()
    })
  end

  post "/api/v1/timeline" do
    AnsibleAppview.Web.Controllers.TimelineController.timeline(conn, conn.body_params)
  end

  get "/api/v1/board-feed" do
    AnsibleAppview.Web.Controllers.TimelineController.board_feed(conn, conn.query_params)
  end

  # Per-board external lane (inbound federation, Task 4b-1). The ONLY path that
  # returns external (source=activitypub) content. Caller must gate on
  # board.external_inclusion (relay policy) AND user opt-in — see the controller
  # moduledoc. `conn.params` carries the `:board_id` path segment + query params.
  get "/api/v1/boards/:board_id/external" do
    AnsibleAppview.Web.Controllers.ExternalController.board_external(conn, conn.params)
  end

  get "/api/v1/home" do
    AnsibleAppview.Web.Controllers.TimelineController.home(conn, conn.query_params)
  end

  # Comments on a content/thread id (murmur/note get a board-less thread keyed by
  # their entity id). `conn.params` carries the `:thread_id` path segment.
  get "/api/v1/thread/:thread_id" do
    AnsibleAppview.Web.Controllers.TimelineController.thread_feed(conn, conn.params)
  end

  get "/api/v1/suggest/follows" do
    AnsibleAppview.Web.Controllers.DiscoveryController.suggest_follows(conn, conn.query_params)
  end

  get "/api/v1/explore" do
    AnsibleAppview.Web.Controllers.DiscoveryController.explore(conn, conn.query_params)
  end

  get "/api/v1/search/actors" do
    AnsibleAppview.Web.Controllers.DiscoveryController.search_actors(conn, conn.query_params)
  end

  get "/api/v1/search" do
    AnsibleAppview.Web.Controllers.DiscoveryController.search(conn, conn.query_params)
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
