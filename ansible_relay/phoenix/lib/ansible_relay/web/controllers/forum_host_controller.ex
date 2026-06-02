defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc """
  Minimal Forum Host discovery surface.

  Boards are host-owned. The app stores local projections and subscriptions.
  This controller intentionally exposes a small JSON contract first; durable
  storage and full signature validation land behind the same routes.
  """

  import Plug.Conn
  alias AnsibleRelay.AbuseDetector
  alias AnsibleRelay.ForumHost.{SignedIntent, Store}
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def info(conn, _params) do
    send_json(conn, 200, Store.host_info())
  end

  def boards(conn, _params) do
    send_json(conn, 200, %{boards: Store.list_boards()})
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
    conn = VerifyWebSession.call(conn, ["forum:post"])

    if conn.halted do
      conn
    else
      title = Map.get(params, "title")

      if is_binary(title) and String.trim(title) != "" do
        case AbuseDetector.check_did(conn.assigns.verified_did) do
          :ok ->
            send_json(conn, 202, %{
              accepted: true,
              subject_did: conn.assigns.verified_did,
              trust_tier: conn.assigns.web_session.trust_tier
            })

          {:error, :rate_limited, detail} ->
            send_json(conn, 429, %{error: "rate_limited", detail: detail})
        end
      else
        send_json(conn, 422, %{error: "invalid_thread"})
      end
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
