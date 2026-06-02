defmodule AnsibleRelay.Web.Controllers.RelayDiscoveryController do
  @moduledoc "App-facing Elix Relay bootstrap discovery."

  import Plug.Conn

  alias AnsibleRelay.ForumHost.Store

  def show(conn, _params) do
    send_json(conn, 200, %{
      version: 1,
      relay: relay_info(),
      announcements: relay_announcements(),
      featured_forum_hosts: featured_forum_hosts(),
      featured_boards: featured_boards(),
      cache: %{
        max_age_seconds:
          Application.get_env(:ansible_relay, :relay_discovery_max_age_seconds, 300)
      }
    })
  end

  defp relay_info do
    %{
      server_kind: "elixRelay",
      origin: Application.get_env(:ansible_relay, :relay_origin, "http://localhost:4001"),
      capabilities: %{
        forum_host_discovery: true,
        relay_announcements: true,
        web_sessions: true
      }
    }
  end

  defp relay_announcements do
    Application.get_env(:ansible_relay, :relay_announcements, [])
  end

  defp featured_forum_hosts do
    Application.get_env(:ansible_relay, :relay_featured_forum_hosts, [
      %{
        "forum_host_id" => Store.forum_host_id(),
        "display_name" => Store.host_info().display_name,
        "forum_host_url" => Store.base_url(),
        "constitution_compliance" => Store.host_info().constitution_compliance
      }
    ])
  end

  defp featured_boards do
    configured = Application.get_env(:ansible_relay, :relay_featured_boards)

    if configured do
      configured
    else
      Store.list_boards()
      |> Enum.map(fn board ->
        %{
          hosted_board_id: board.hosted_board_id,
          title: board.title,
          description: board.description,
          forum_host_url: Store.base_url(),
          canonical_board_uri: board.canonical_board_uri,
          constitution_compliance: Store.host_info().constitution_compliance,
          tags: board.tags,
          language: board.language
        }
      end)
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
