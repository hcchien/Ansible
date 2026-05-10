defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc """
  Minimal Forum Host discovery surface.

  Boards are host-owned. The app stores local projections and subscriptions.
  This controller intentionally exposes a small JSON contract first; durable
  storage and full signature validation land behind the same routes.
  """

  import Plug.Conn

  @default_base_url "http://localhost:4001"

  def info(conn, _params) do
    send_json(conn, 200, host_info())
  end

  def boards(conn, _params) do
    send_json(conn, 200, %{boards: default_boards()})
  end

  def create_board(conn, params) do
    with :ok <- require_fields(params, ["intent_id", "author_did", "signature"]),
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
      {:error, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

      _ ->
        send_json(conn, 422, %{error: "invalid_board"})
    end
  end

  defp host_info do
    %{
      forum_host_id: "host-local-dev",
      display_name: "Local Forum Host",
      base_url: base_url(),
      canonical_host_uri: base_url(),
      server_kind: "ansibleForumHost",
      capabilities: %{
        create_boards: true,
        create_threads: true,
        cross_post: true
      }
    }
  end

  defp default_boards do
    [
      %{
        hosted_board_id: "general",
        canonical_board_uri: "#{base_url()}/boards/general",
        slug: "general",
        title: "General",
        description: "General discussion",
        permissions: %{"read" => true, "write" => true}
      }
    ]
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
