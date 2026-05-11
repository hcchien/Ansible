defmodule AnsibleRelay.Web.Router do
  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:put_cors_headers)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  options _ do
    send_resp(conn, 204, "")
  end

  get "/health" do
    send_json(conn, 200, %{status: "ok", relay: "ansible_relay", version: "0.1.0"})
  end

  # ActivityPub discovery and relay-owned actor endpoints
  get "/.well-known/webfinger" do
    AnsibleRelay.Web.Controllers.ActivityPubController.webfinger(conn, conn.query_params)
  end

  get "/users/:actor" do
    AnsibleRelay.Web.Controllers.ActivityPubController.actor(conn, %{"actor" => actor})
  end

  post "/users/:actor/inbox" do
    AnsibleRelay.Web.Controllers.ActivityPubController.inbox(conn, %{"actor" => actor})
  end

  get "/users/:actor/outbox" do
    AnsibleRelay.Web.Controllers.ActivityPubController.outbox(conn, %{"actor" => actor})
  end

  # Phase 1 — Identity Anchoring
  post "/api/v1/identity/challenge" do
    AnsibleRelay.Web.Controllers.IdentityController.challenge(conn, conn.body_params)
  end

  post "/api/v1/identity/anchor" do
    AnsibleRelay.Web.Controllers.IdentityController.anchor(conn, conn.body_params)
  end

  # Phase 2 — Op ingestion
  post "/api/v1/ops" do
    AnsibleRelay.Web.Controllers.OpsController.ingest(conn, conn.body_params)
  end

  # Federation — signed publication intents for relay-managed distribution
  post "/api/v1/publication-intents" do
    AnsibleRelay.Web.Controllers.PublicationIntentController.create(conn, conn.body_params)
  end

  # Phase 2 — Delta pull (cursor-based)
  get "/api/v1/ops/delta" do
    AnsibleRelay.Web.Controllers.OpsController.delta(conn, conn.query_params)
  end

  # Forum Host — hosted-board discovery and creation
  get "/api/v1/forum-host" do
    AnsibleRelay.Web.Controllers.ForumHostController.info(conn, conn.query_params)
  end

  get "/api/v1/forum-host/boards" do
    AnsibleRelay.Web.Controllers.ForumHostController.boards(conn, conn.query_params)
  end

  post "/api/v1/forum-host/boards" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_board(conn, conn.body_params)
  end

  post "/api/v1/forum-host/web/threads" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_web_thread(conn, conn.body_params)
  end

  # App-mediated web sessions
  post "/api/v1/web-sessions/challenges" do
    AnsibleRelay.Web.Controllers.WebSessionController.create_challenge(conn, conn.body_params)
  end

  get "/api/v1/web-sessions/challenges/:id" do
    AnsibleRelay.Web.Controllers.WebSessionController.poll_challenge(conn, %{
      "challenge_id" => id
    })
  end

  post "/api/v1/web-sessions/approve" do
    AnsibleRelay.Web.Controllers.WebSessionController.approve(conn, conn.body_params)
  end

  post "/api/v1/web-sessions/reject" do
    AnsibleRelay.Web.Controllers.WebSessionController.reject(conn, conn.body_params)
  end

  post "/api/v1/web-sessions/revoke" do
    AnsibleRelay.Web.Controllers.WebSessionController.revoke(conn, conn.body_params)
  end

  get "/api/v1/web-sessions" do
    AnsibleRelay.Web.Controllers.WebSessionController.list(conn, conn.query_params)
  end

  get "/api/v1/web-sessions/me" do
    AnsibleRelay.Web.Controllers.WebSessionController.me(conn, conn.req_headers)
  end

  # V2 — Passkeys Identity
  post "/api/v2/identity/register" do
    AnsibleRelay.Web.Controllers.IdentityV2Controller.register(conn, conn.body_params)
  end

  post "/api/v2/identity/anchor" do
    AnsibleRelay.Web.Controllers.IdentityV2Controller.anchor(conn, conn.body_params)
  end

  # V2 — Reputation / VP presentation
  post "/api/v2/reputation/present" do
    AnsibleRelay.Web.Controllers.ReputationController.present(conn, conn.body_params)
  end

  # XRPC — AT Protocol
  post "/xrpc/com.atproto.repo.createRecord" do
    AnsibleRelay.Web.Controllers.XrpcController.create_record(conn, conn.body_params)
  end

  get "/xrpc/com.atproto.identity.resolveHandle" do
    AnsibleRelay.Web.Controllers.XrpcController.resolve_handle(conn, conn.query_params)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp put_cors_headers(conn, _opts) do
    case allowed_web_origin(conn) do
      nil ->
        conn

      origin ->
        conn
        |> Plug.Conn.put_resp_header("access-control-allow-origin", origin)
        |> Plug.Conn.put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
        |> Plug.Conn.put_resp_header(
          "access-control-allow-headers",
          "authorization, content-type"
        )
        |> Plug.Conn.put_resp_header("access-control-max-age", "600")
        |> Plug.Conn.put_resp_header("vary", "origin")
    end
  end

  defp allowed_web_origin(conn) do
    allowed_origins =
      Application.get_env(:ansible_relay, :web_allowed_origins, [
        "http://localhost:5173",
        "http://127.0.0.1:5173"
      ])

    case Plug.Conn.get_req_header(conn, "origin") do
      [origin | _] ->
        if origin in allowed_origins, do: origin

      _ ->
        nil
    end
  end
end
