defmodule AnsibleRelay.Web.ForumHostControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp get_json(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  test "GET /api/v1/forum-host returns Forum Host metadata" do
    response = get_json("/api/v1/forum-host")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["forum_host_id"] == "host-local-dev"
    assert body["server_kind"] == "ansibleForumHost"
    assert body["capabilities"]["create_boards"] == true
  end

  test "GET /api/v1/forum-host/boards returns hosted boards" do
    response = get_json("/api/v1/forum-host/boards")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert is_list(body["boards"])

    board = List.first(body["boards"])
    assert board["hosted_board_id"] == "general"
    assert board["canonical_board_uri"] == "http://localhost:4001/boards/general"
  end

  test "POST /api/v1/forum-host/boards accepts signed create-board intent" do
    response =
      post_json("/api/v1/forum-host/boards", %{
        "intent_id" => "intent-1",
        "author_did" => "did:key:z6MkUser",
        "signature" => "sig-hex",
        "board" => %{
          "title" => "Reading Group",
          "description" => "Open discussion"
        }
      })

    assert response.status == 201

    body = Jason.decode!(response.resp_body)
    assert body["hosted_board_id"] == "reading-group"
    assert body["slug"] == "reading-group"
    assert body["title"] == "Reading Group"
  end
end
