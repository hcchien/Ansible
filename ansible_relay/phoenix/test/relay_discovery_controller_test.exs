defmodule AnsibleRelay.Web.RelayDiscoveryControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    original_relay_origin = Application.get_env(:ansible_relay, :relay_origin)
    original_announcements = Application.get_env(:ansible_relay, :relay_announcements)

    original_featured_forum_hosts =
      Application.get_env(:ansible_relay, :relay_featured_forum_hosts)

    original_featured_boards = Application.get_env(:ansible_relay, :relay_featured_boards)

    original_max_age_seconds =
      Application.get_env(:ansible_relay, :relay_discovery_max_age_seconds)

    Application.put_env(:ansible_relay, :relay_origin, "https://relay.trisaura.test")
    Application.delete_env(:ansible_relay, :relay_discovery_max_age_seconds)

    Application.put_env(:ansible_relay, :relay_announcements, [
      %{
        "announcement_id" => "relay-status",
        "owner_kind" => "relay",
        "title" => "Relay online",
        "body" => "Relay discovery is available.",
        "severity" => "info",
        "locale" => "en"
      }
    ])

    Application.put_env(:ansible_relay, :relay_featured_forum_hosts, [
      %{
        "forum_host_id" => "external-host",
        "display_name" => "External Forum Host",
        "forum_host_url" => "https://forum.trisaura.test"
      },
      %{
        "forum_host_id" => "compatible-host",
        "display_name" => "Compatible Forum Host",
        "forum_host_url" => "https://compatible-forum.trisaura.test",
        "constitution_compliance" => "compatible"
      }
    ])

    Application.put_env(:ansible_relay, :relay_featured_boards, [
      %{
        "forum_host_url" => "https://forum.trisaura.test",
        "canonical_board_uri" => "https://forum.trisaura.test/boards/general",
        "hosted_board_id" => "general",
        "title" => "General",
        "description" => "Start here"
      },
      %{
        "forum_host_url" => "https://compatible-forum.trisaura.test",
        "canonical_board_uri" => "https://compatible-forum.trisaura.test/boards/local-news",
        "hosted_board_id" => "local-news",
        "title" => "Local News",
        "description" => "Compatible host board",
        "constitution_compliance" => "compatible"
      }
    ])

    on_exit(fn ->
      restore_env(:relay_origin, original_relay_origin)
      restore_env(:relay_announcements, original_announcements)
      restore_env(:relay_featured_forum_hosts, original_featured_forum_hosts)
      restore_env(:relay_featured_boards, original_featured_boards)
      restore_env(:relay_discovery_max_age_seconds, original_max_age_seconds)
    end)

    :ok
  end

  test "GET /api/v1/discovery returns Relay bootstrap catalog" do
    response =
      conn(:get, "/api/v1/discovery")
      |> Router.call(@router_opts)

    assert response.status == 200
    body = Jason.decode!(response.resp_body)

    assert body["version"] == 1
    assert body["relay"]["server_kind"] == "elixRelay"
    assert body["relay"]["origin"] == "https://relay.trisaura.test"
    assert body["relay"]["capabilities"]["forum_host_discovery"] == true
    assert body["relay"]["capabilities"]["relay_announcements"] == true
    assert body["relay"]["capabilities"]["web_sessions"] == true

    assert [%{"announcement_id" => "relay-status", "owner_kind" => "relay"}] =
             body["announcements"]

    assert [general_board, local_news_board] = body["featured_boards"]
    assert general_board["hosted_board_id"] == "general"
    assert general_board["forum_host_url"] == "https://forum.trisaura.test"
    assert general_board["title"] == "General"
    assert general_board["description"] == "Start here"
    assert general_board["constitution_compliance"] == "unknown"

    assert local_news_board["hosted_board_id"] == "local-news"
    assert local_news_board["forum_host_url"] == "https://compatible-forum.trisaura.test"
    assert local_news_board["title"] == "Local News"
    assert local_news_board["constitution_compliance"] == "compatible"

    assert [external_host, compatible_host] = body["featured_forum_hosts"]
    assert external_host["forum_host_id"] == "external-host"
    assert external_host["display_name"] == "External Forum Host"
    assert external_host["forum_host_url"] == "https://forum.trisaura.test"
    assert external_host["constitution_compliance"] == "unknown"

    assert compatible_host["forum_host_id"] == "compatible-host"
    assert compatible_host["display_name"] == "Compatible Forum Host"
    assert compatible_host["forum_host_url"] == "https://compatible-forum.trisaura.test"
    assert compatible_host["constitution_compliance"] == "compatible"

    assert body["cache"]["max_age_seconds"] == 300
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
