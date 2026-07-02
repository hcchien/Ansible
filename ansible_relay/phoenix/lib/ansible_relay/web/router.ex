defmodule AnsibleRelay.Web.Router do
  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:put_cors_headers)
  plug(AnsibleRelay.Web.Plugs.RequireProtocolVersion)
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

  # Liveness: cheap, no I/O — safe for a fast TCP/startup probe.
  get "/health" do
    send_json(conn, 200, %{status: "ok", relay: "ansible_relay", version: "0.1.0"})
  end

  # Readiness: cheap DB ping so a dead/exhausted pool reports unhealthy and the
  # load balancer stops routing to this instance. Kept separate from /health so
  # the liveness probe never fails on a transient DB blip.
  get "/readyz" do
    case db_ready?() do
      :ok ->
        send_json(conn, 200, %{status: "ready", relay: "ansible_relay"})

      {:error, reason} ->
        send_json(conn, 503, %{status: "unavailable", reason: reason})
    end
  end

  # Phase 0 — Observability baseline (G17): Prometheus metrics scrape target.
  # Deliberately outside /api/* so the protocol-version plug never gates it.
  get "/metrics" do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain; version=0.0.4")
    |> Plug.Conn.send_resp(200, AnsibleRelay.Metrics.render())
  end

  # Phase 0 — API versioning: advertise the protocol versions this relay
  # speaks so clients can detect upgrade requirements before they break.
  get "/api/v1/meta" do
    send_json(conn, 200, %{
      service: "ansible_relay",
      version: "0.1.0",
      protocol: AnsibleRelay.Protocol.advertisement()
    })
  end

  get "/api/v1/discovery" do
    AnsibleRelay.Web.Controllers.RelayDiscoveryController.show(conn, conn.query_params)
  end

  # ActivityPub discovery and relay-owned actor endpoints
  get "/.well-known/webfinger" do
    AnsibleRelay.Web.Controllers.ActivityPubController.webfinger(conn, conn.query_params)
  end

  # OS universal-link association files (outbound sharing loop). Fail-closed:
  # 404 until the app identifiers are configured via environment variables.
  get "/.well-known/apple-app-site-association" do
    AnsibleRelay.Web.Controllers.AppAssociationController.apple(conn, %{})
  end

  # Apple also probes the pre-iOS-9.3 root path; serve the same document.
  get "/apple-app-site-association" do
    AnsibleRelay.Web.Controllers.AppAssociationController.apple(conn, %{})
  end

  get "/.well-known/assetlinks.json" do
    AnsibleRelay.Web.Controllers.AppAssociationController.android(conn, %{})
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

  # Self-certifying identity anchor (the legacy ZKP challenge/anchor flow was
  # retired in favour of did:elix + this self-certifying object).
  post "/api/v1/identity/anchor" do
    AnsibleRelay.Web.Controllers.IdentityAnchorController.submit(conn, conn.body_params)
  end

  post "/api/v1/identity/anchor/promote" do
    AnsibleRelay.Web.Controllers.IdentityAnchorController.promote(conn, conn.body_params)
  end

  post "/api/v1/identity/anchor/veto" do
    AnsibleRelay.Web.Controllers.IdentityAnchorController.veto(conn, conn.body_params)
  end

  get "/api/v1/identity/anchor/:did" do
    AnsibleRelay.Web.Controllers.IdentityAnchorController.show(conn, %{"did" => did})
  end

  # did:elix resolution → projected W3C DID document (layered identity).
  get "/api/v1/identity/did/:did" do
    AnsibleRelay.Web.Controllers.IdentityAnchorController.resolve_did(conn, %{"did" => did})
  end

  get "/api/v1/identity/public-key/:did" do
    AnsibleRelay.Web.Controllers.IdentityController.public_key(conn, %{"did" => did})
  end

  get "/api/v1/identity/handle/:did" do
    AnsibleRelay.Web.Controllers.IdentityController.handle(conn, %{"did" => did})
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

  # Phase 2.3 — Signed snapshot: consumers fold this then apply the delta after
  # snapshot.cursor to rebuild a read model without replaying full op history.
  get "/api/v1/ops/snapshot" do
    AnsibleRelay.Web.Controllers.OpsController.snapshot(conn, conn.query_params)
  end

  # Forum Host — hosted-board discovery and creation
  get "/api/v1/forum-host" do
    AnsibleRelay.Web.Controllers.ForumHostController.info(conn, conn.query_params)
  end

  get "/api/v1/forum-host/boards" do
    AnsibleRelay.Web.Controllers.ForumHostController.boards(conn, conn.query_params)
  end

  get "/api/v1/forum-host/boards/created-by/:did" do
    AnsibleRelay.Web.Controllers.ForumHostController.boards_created_by(conn, did)
  end

  get "/api/v1/discover/boards" do
    AnsibleRelay.Web.Controllers.ForumHostController.discover_boards(conn, conn.query_params)
  end

  # Public thread metadata for shared-link previews (outbound sharing loop).
  get "/api/v1/forum-host/threads/:thread_id/preview" do
    AnsibleRelay.Web.Controllers.ForumHostController.thread_preview(conn, thread_id)
  end

  get "/api/v1/forum-host/announcements" do
    AnsibleRelay.Web.Controllers.ForumHostController.announcements(conn, conn.query_params)
  end

  post "/api/v1/forum-host/boards" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_board(conn, conn.body_params)
  end

  post "/api/v1/forum-host/web/threads" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_web_thread(conn, conn.body_params)
  end

  # Forum Host — content reporting (signed-intent and web-session rails)
  post "/api/v1/forum-host/reports" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_report(conn, conn.body_params)
  end

  post "/api/v1/forum-host/web/reports" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_web_report(conn, conn.body_params)
  end

  # Forum Host — moderation console (board moderators only)
  get "/api/v1/forum-host/web/moderation/reports" do
    AnsibleRelay.Web.Controllers.ForumHostController.list_web_moderation_reports(
      conn,
      conn.query_params
    )
  end

  post "/api/v1/forum-host/web/moderation/actions" do
    AnsibleRelay.Web.Controllers.ForumHostController.create_web_moderation_action(
      conn,
      conn.body_params
    )
  end

  get "/api/v1/forum-host/web/moderation/actions" do
    AnsibleRelay.Web.Controllers.ForumHostController.list_web_moderation_actions(
      conn,
      conn.query_params
    )
  end

  # Forum Host — public, reason-coded moderation state for a board
  get "/api/v1/forum-host/boards/:board_id/moderation-state" do
    AnsibleRelay.Web.Controllers.ForumHostController.board_moderation_state(conn, board_id)
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

  # Encrypted messenger relay
  post "/api/v1/messenger/devices" do
    AnsibleRelay.Web.Controllers.MessengerController.publish_device(conn, conn.body_params)
  end

  post "/api/v1/messenger/pre-keys" do
    AnsibleRelay.Web.Controllers.MessengerController.publish_pre_keys(conn, conn.body_params)
  end

  get "/api/v1/messenger/devices/:subject_did" do
    AnsibleRelay.Web.Controllers.MessengerController.devices(conn, %{
      "subject_did" => subject_did
    })
  end

  get "/api/v1/messenger/pre-key-bundles/:subject_did" do
    AnsibleRelay.Web.Controllers.MessengerController.pre_key_bundle(conn, %{
      "subject_did" => subject_did
    })
  end

  post "/api/v1/messenger/messages" do
    AnsibleRelay.Web.Controllers.MessengerController.send_message(conn, conn.body_params)
  end

  get "/api/v1/messenger/messages" do
    AnsibleRelay.Web.Controllers.MessengerController.mailbox(conn, conn.query_params)
  end

  post "/api/v1/messenger/messages/:message_id/ack" do
    AnsibleRelay.Web.Controllers.MessengerController.ack(
      conn,
      Map.put(conn.body_params, "message_id", message_id)
    )
  end

  # Phase B notifications — push token registry (signed; wake payloads are
  # content-free by construction)
  post "/api/v1/push/tokens" do
    AnsibleRelay.Web.Controllers.PushController.register(conn, conn.body_params)
  end

  post "/api/v1/push/tokens/unregister" do
    AnsibleRelay.Web.Controllers.PushController.unregister(conn, conn.body_params)
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

  # Cheap round-trip to Postgres. A short timeout means a stuck pool reports
  # unhealthy quickly rather than hanging the readiness probe.
  defp db_ready? do
    case AnsibleRelay.Repo.query("SELECT 1", [], timeout: 2_000) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "database_unavailable"}
    end
  rescue
    _ -> {:error, "database_unavailable"}
  catch
    :exit, _ -> {:error, "database_unavailable"}
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
        |> Plug.Conn.put_resp_header("access-control-allow-credentials", "true")
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
