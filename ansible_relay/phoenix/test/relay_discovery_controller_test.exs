defmodule AnsibleRelay.Web.RelayDiscoveryControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    original_relay_origin = Application.get_env(:ansible_relay, :relay_origin)
    original_announcements = Application.get_env(:ansible_relay, :relay_announcements)
    original_featured_boards = Application.get_env(:ansible_relay, :relay_featured_boards)

    Application.put_env(:ansible_relay, :relay_origin, "https://relay.trisaura.test")

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

    Application.put_env(:ansible_relay, :relay_featured_boards, [
      %{
        "forum_host_url" => "https://forum.trisaura.test",
        "canonical_board_uri" => "https://forum.trisaura.test/boards/general",
        "hosted_board_id" => "general",
        "title" => "General",
        "description" => "Start here"
      }
    ])

    on_exit(fn ->
      restore_env(:relay_origin, original_relay_origin)
      restore_env(:relay_announcements, original_announcements)
      restore_env(:relay_featured_boards, original_featured_boards)
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

    assert [%{"hosted_board_id" => "general"}] = body["featured_boards"]

    assert [%{"forum_host_id" => "host-local-dev", "constitution_compliance" => _}] =
             body["featured_forum_hosts"]

    assert body["cache"]["max_age_seconds"] == 300
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
