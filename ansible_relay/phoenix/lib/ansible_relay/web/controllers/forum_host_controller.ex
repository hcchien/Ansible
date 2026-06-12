defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc """
  Minimal Forum Host discovery surface.

  Boards are host-owned. The app stores local projections and subscriptions.
  This controller intentionally exposes a small JSON contract first; durable
  storage and full signature validation land behind the same routes.
  """

  import Plug.Conn
  alias AnsibleRelay.AbuseDetector
  alias AnsibleRelay.ForumHost.{PostingGate, SignedIntent, Store}
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def info(conn, _params) do
    send_json(conn, 200, Store.host_info())
  end

  def boards(conn, _params) do
    send_json(conn, 200, %{boards: Store.list_boards()})
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

          {:error, :rate_limited, detail} ->
            send_json(conn, 429, %{error: "rate_limited", detail: detail})
        end
      else
        send_json(conn, 422, %{error: "invalid_thread"})
      end
    end
  end

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
