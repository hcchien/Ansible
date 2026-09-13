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

  get "/api/v1/content/:type/:id" do
    case AnsibleAppview.Timeline.content(type, id) do
      {:ok, item} -> send_json(conn, 200, %{item: item})
      {:error, :deleted} -> send_json(conn, 410, %{error: "content_deleted"})
      {:error, _} -> send_json(conn, 404, %{error: "content_not_found"})
    end
  end

  # Public, root-signature verified authority evidence. Native clients use their
  # configured AppView directly; a Relay response cannot acknowledge this state.
  post "/api/v1/authority/checkpoint" do
    case AnsibleAppview.Authority.Witness.checkpoint(
           conn.body_params["did"],
           conn.body_params["chain"]
         ) do
      {:ok, result} ->
        send_json(conn, 200, result)

      {:error, :recovery_observation_pending} ->
        send_json(conn, 202, %{state: "pending", error: "recovery_observation_pending"})

      {:error, reason} ->
        send_json(conn, 409, %{error: reason})
    end
  end

  post "/api/v1/authority/revalidate" do
    case AnsibleAppview.Authority.Witness.revalidate(
           conn.body_params["operation"],
           conn.body_params["authorization"],
           conn.body_params["did_signature"]
         ) do
      {:ok, result} ->
        {indexed, _} =
          AnsibleAppview.Authority.Witness.retry_pending(conn.body_params["operation"])

        send_json(conn, 200, Map.put(result, :indexed, indexed))

      {:error, reason} ->
        send_json(conn, 409, %{error: reason})
    end
  end

  post "/api/v1/authority/veto" do
    case AnsibleAppview.Authority.Witness.veto(
           conn.body_params["did"],
           conn.body_params["pending_anchor_cid"],
           conn.body_params["veto_sig"],
           conn.body_params["canonical_body"]
         ) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, reason} -> send_json(conn, 409, %{error: reason})
    end
  end

  post "/api/v1/authority/revoke" do
    case AnsibleAppview.Authority.Witness.revoke(
           conn.body_params["revocation"],
           conn.body_params["did_signature"]
         ) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, reason} -> send_json(conn, 409, %{error: reason})
    end
  end

  post "/api/v1/timeline" do
    AnsibleAppview.Web.Controllers.TimelineController.timeline(conn, conn.body_params)
  end

  get "/api/v1/board-feed" do
    AnsibleAppview.Web.Controllers.TimelineController.board_feed(conn, conn.query_params)
  end

  get "/api/v1/context-notes" do
    AnsibleAppview.Web.Controllers.ContextNotesController.index(conn, conn.query_params)
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

  # Public profile ops are an explicit directory opt-in. This endpoint never
  # consults relay account records or returns private profile fields.
  get "/api/v1/profiles/:did" do
    AnsibleAppview.Web.Controllers.DiscoveryController.profile(conn, conn.params)
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
