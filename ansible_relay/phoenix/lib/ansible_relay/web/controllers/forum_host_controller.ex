defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc """
  Minimal Forum Host discovery surface.

  Boards are host-owned. The app stores local projections and subscriptions.
  This controller intentionally exposes a small JSON contract first; durable
  storage and full signature validation land behind the same routes.
  """

  import Plug.Conn
  alias AnsibleRelay.AbuseDetector
  alias AnsibleRelay.ForumHost.Store
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  @default_base_url "http://localhost:4001"

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
    conn = VerifyWebSession.call(conn, ["forum:post"])

    if conn.halted do
      conn
    else
      with :ok <- require_fields(params, ["intent_id", "author_did", "signature"]),
           :ok <- check_author_matches_session(conn.assigns.verified_did, params["author_did"]),
           %{"title" => title} = board when is_binary(title) <- Map.get(params, "board") do
        slug = slugify(title)

        send_json(conn, 201, %{
          hosted_board_id: slug,
          canonical_board_uri: "#{base_url()}/boards/#{slug}",
          slug: slug,
          title: title,
          description: Map.get(board, "description"),
          permissions: %{"read" => true, "write" => true}
        })
      else
        {:error, :author_mismatch} ->
          send_json(conn, 403, %{error: "author_did_mismatch"})

        {:error, fields} ->
          send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

        _ ->
          send_json(conn, 422, %{error: "invalid_board"})
      end
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

  defp check_author_matches_session(session_did, author_did) do
    if session_did == author_did, do: :ok, else: {:error, :author_mismatch}
  end

  defp require_fields(params, fields) do
    missing =
      fields
      |> Enum.reject(fn field ->
        case Map.get(params, field) do
          value when is_binary(value) -> String.trim(value) != ""
          nil -> false
          _ -> true
        end
      end)

    if missing == [], do: :ok, else: {:error, missing}
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "board"
      slug -> slug
    end
  end

  defp base_url do
    Application.get_env(:ansible_relay, :forum_host_base_url, @default_base_url)
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
