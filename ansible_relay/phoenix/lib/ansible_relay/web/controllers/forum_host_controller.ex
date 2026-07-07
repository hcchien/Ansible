defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc """
  Minimal Forum Host discovery surface.

  Boards are host-owned. The app stores local projections and subscriptions.
  This controller intentionally exposes a small JSON contract first; durable
  storage and full signature validation land behind the same routes.
  """

  import Plug.Conn
  alias AnsibleRelay.AbuseDetector
  alias AnsibleRelay.ForumHost.{Moderation, PostingGate, SignedIntent, Store}
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def info(conn, _params) do
    send_json(conn, 200, Store.host_info())
  end

  def boards(conn, _params) do
    send_json(conn, 200, %{boards: Store.list_boards()})
  end

  # GET /api/v1/forum-host/boards/created-by/:did — boards this DID authored, so
  # a reinstalled client can re-list its own boards (subscriptions are local).
  def boards_created_by(conn, did) do
    send_json(conn, 200, %{boards: Store.list_boards_created_by(did)})
  end

  # GET /api/v1/forum-host/threads/:thread_id/preview — public metadata for a
  # shared thread link (outbound sharing loop): the web frontend's OG injector
  # uses it to render a thread-specific preview instead of falling back to the
  # board description. Removal tombstones win: a removed thread 404s with its
  # public reason code rather than leaking the stripped payload.
  def thread_preview(conn, thread_id) do
    case AnsibleRelay.OpStore.create_op("thread", thread_id) do
      nil ->
        send_json(conn, 404, %{error: "thread_not_found"})

      op ->
        case Moderation.overlay_ops([op]) do
          [%{removed: true, reason_code: reason}] ->
            send_json(conn, 404, %{error: "thread_removed", reason_code: reason})

          [visible] ->
            send_json(conn, 200, thread_preview_body(thread_id, visible))
        end
    end
  end

  defp thread_preview_body(thread_id, op) do
    payload = decode_op_payload(op.payload)
    {reply_count, first_reply} = AnsibleRelay.OpStore.thread_reply_stats(thread_id)

    excerpt =
      case first_reply && decode_op_payload(first_reply.payload) do
        %{"content" => content} when is_binary(content) -> truncate_excerpt(content)
        _ -> nil
      end

    %{
      thread_id: thread_id,
      board_id: payload["boardId"],
      title: payload["title"],
      author_did: op.author_did,
      author_handle: author_handle(op.author_did),
      created_at: payload["createdAt"] || op.received_at,
      reply_count: reply_count,
      excerpt: excerpt,
      locked: Map.get(op, :locked, false)
    }
  end

  defp decode_op_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_op_payload(_payload), do: %{}

  defp truncate_excerpt(content) do
    trimmed = String.trim(content)
    if String.length(trimmed) > 200, do: String.slice(trimmed, 0, 200) <> "…", else: trimmed
  end

  defp author_handle(did) do
    case AnsibleRelay.DidAccountCache.get(did) do
      {:ok, %{handle: handle}} when is_binary(handle) and handle != "" -> handle
      _ -> nil
    end
  end

  # GET /api/v1/discover/boards?q=&limit=  (empty q -> browse all)
  def discover_boards(conn, params) do
    q = params["q"] || ""

    limit =
      case Integer.parse(to_string(params["limit"] || "")) do
        {n, _} -> n
        :error -> 20
      end

    send_json(conn, 200, %{boards: Store.search_boards(q, limit)})
  end

  def announcements(conn, _params) do
    send_json(conn, 200, %{announcements: Store.list_announcements("forum_host")})
  end

  def create_board(conn, params) do
    case SignedIntent.verify_create_board(params) do
      {:ok, intent} ->
        case Store.create_board(intent) do
          {:ok, board} -> send_json(conn, 201, board)
          {:error, :duplicate_intent} -> send_json(conn, 409, %{error: "duplicate_intent"})
          {:error, error} -> send_json(conn, 422, %{error: error_string(error)})
        end

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  # POST /api/v1/forum-host/boards/:board_id/update — signed-intent board
  # management: only the board's creator DID may update title, description,
  # or posting_policy. Same fail-closed envelope checks as create_board.
  def update_board(conn, board_id, params) do
    case SignedIntent.verify_update_board(params) do
      {:ok, intent} ->
        if intent.board_id == board_id do
          apply_board_update(conn, intent)
        else
          send_json(conn, 422, %{error: "board_id_mismatch"})
        end

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  defp apply_board_update(conn, intent) do
    case Store.update_board(intent) do
      {:ok, board} -> send_json(conn, 200, board)
      {:error, :board_not_found} -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, :not_board_creator} -> send_json(conn, 403, %{error: "not_board_creator"})
      {:error, :duplicate_intent} -> send_json(conn, 409, %{error: "duplicate_intent"})
      {:error, error} -> send_json(conn, 422, %{error: error_string(error)})
    end
  end

  def create_web_thread(conn, params) do
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      title = Map.get(params, "title")

      if is_binary(title) and String.trim(title) != "" do
        with {:ok, board} <- resolve_web_thread_board(params),
             # Tier gate runs at acceptance time on the session DID — cookie
             # writes get the identical posting_policy check as signed ops.
             :ok <- PostingGate.authorize_post(board, conn.assigns.verified_did),
             # Lock gate: posting into a locked thread is rejected at the
             # same chokepoint, with the lock's reason code.
             :ok <- authorize_web_thread_lock(params),
             :ok <- AbuseDetector.check_did(conn.assigns.verified_did) do
          send_json(conn, 202, %{
            accepted: true,
            subject_did: conn.assigns.verified_did,
            trust_tier: conn.assigns.web_session.trust_tier
          })
        else
          {:error, :board_not_found} ->
            send_json(conn, 404, %{error: "board_not_found"})

          {:error, :posting_requires_tier, required_tier, current_tier} ->
            send_json(conn, 403, %{
              error: "posting_requires_tier",
              required_tier: required_tier,
              current_tier: current_tier
            })

          {:error, :thread_locked, reason_code} ->
            send_json(conn, 403, %{error: "thread_locked", reason_code: reason_code})

          {:error, :rate_limited, detail} ->
            send_json(conn, 429, %{error: "rate_limited", detail: detail})
        end
      else
        send_json(conn, 422, %{error: "invalid_thread"})
      end
    end
  end

  # --- Content reporting (web-session rail) ---

  # POST /api/v1/forum-host/web/reports
  def create_web_report(conn, params) do
    AnsibleRelay.Metrics.inc("relay_reports_total", %{rail: "web_session"})
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      result =
        Moderation.create_report(%{
          reporter_did: conn.assigns.verified_did,
          target_kind: params["target_kind"],
          target_ref: params["target_ref"],
          board_id: params["board_id"],
          reason_code: params["reason_code"],
          note: params["note"]
        })

      send_report_result(conn, result)
    end
  end

  # --- Content reporting (signed-intent rail) ---

  # POST /api/v1/forum-host/reports
  def create_report(conn, params) do
    AnsibleRelay.Metrics.inc("relay_reports_total", %{rail: "signed_intent"})

    case SignedIntent.verify_report_content(params) do
      {:ok, attrs} ->
        send_report_result(conn, Moderation.create_report(attrs))

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  # --- Moderation console (web-session rail, board moderators only) ---

  # GET /api/v1/forum-host/web/moderation/reports?status=open
  def list_web_moderation_reports(conn, params) do
    conn = VerifyWebSession.call(conn, ["forum:read"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      case Moderation.list_reports(conn.assigns.verified_did, params["status"] || "open") do
        {:ok, reports} -> send_json(conn, 200, %{reports: reports})
        {:error, :not_board_moderator} -> send_json(conn, 403, %{error: "not_board_moderator"})
      end
    end
  end

  # POST /api/v1/forum-host/web/moderation/actions
  def create_web_moderation_action(conn, params) do
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      result =
        Moderation.create_action(%{
          moderator_did: conn.assigns.verified_did,
          action: params["action"],
          target_ref: params["target_ref"],
          board_id: params["board_id"],
          reason_code: params["reason_code"],
          report_id: parse_report_id(params["report_id"])
        })

      case result do
        {:ok, action} ->
          send_json(conn, 201, %{action: action})

        {:error, :not_board_moderator} ->
          send_json(conn, 403, %{error: "not_board_moderator"})

        {:error, error} ->
          send_json(conn, 422, %{error: error_string(error)})
      end
    end
  end

  # GET /api/v1/forum-host/web/moderation/actions — the audit list.
  def list_web_moderation_actions(conn, _params) do
    conn = VerifyWebSession.call(conn, ["forum:read"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      case Moderation.list_actions(conn.assigns.verified_did) do
        {:ok, actions} -> send_json(conn, 200, %{actions: actions})
        {:error, :not_board_moderator} -> send_json(conn, 403, %{error: "not_board_moderator"})
      end
    end
  end

  # GET /api/v1/forum-host/boards/:board_id/moderation-state — public:
  # tombstone refs and lock states are reason-coded and visible to everyone,
  # including the affected author (constitution Base Rule 6).
  def board_moderation_state(conn, board_id) do
    case PostingGate.get_board(board_id) do
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      board -> send_json(conn, 200, Moderation.moderation_state(board.hosted_board_id))
    end
  end

  defp send_report_result(conn, result) do
    case result do
      {:ok, :created, report} ->
        send_json(conn, 201, %{report: report})

      {:ok, :duplicate, report} ->
        send_json(conn, 200, %{report: report})

      {:error, :rate_limited, _detail} ->
        send_json(conn, 429, %{error: "rate_limited"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  defp authorize_web_thread_lock(params) do
    case Map.get(params, "thread_id") do
      thread_id when is_binary(thread_id) -> Moderation.authorize_thread_post(thread_id)
      _absent -> :ok
    end
  end

  defp parse_report_id(value) when is_integer(value), do: value

  defp parse_report_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _other -> nil
    end
  end

  defp parse_report_id(_value), do: nil

  # board_id is optional for backward compatibility (the endpoint predates
  # board-scoped web threads), but when present it must resolve to a hosted
  # board so a gated board cannot be bypassed with a mistyped id.
  defp resolve_web_thread_board(params) do
    case Map.get(params, "board_id") || Map.get(params, "hosted_board_id") do
      nil ->
        {:ok, nil}

      board_id when is_binary(board_id) ->
        case PostingGate.get_board(board_id) do
          nil -> {:error, :board_not_found}
          board -> {:ok, board}
        end

      _invalid ->
        {:error, :board_not_found}
    end
  end

  defp error_string(error) when is_atom(error), do: Atom.to_string(error)
  defp error_string(error), do: inspect(error)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
