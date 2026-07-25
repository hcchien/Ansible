defmodule AnsibleRelay.Web.ThreadPreviewTest do
  @moduledoc """
  GET /api/v1/forum-host/threads/:thread_id/preview — public metadata for
  shared thread links (outbound sharing loop): title/author/reply stats from
  the op log, with moderation removal tombstones winning over content.
  """

  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Db.{ForumHostBoard, ForumHostModerationAction}
  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{OpStore, Repo}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case AnsibleRelay.DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.insert!(%ForumHostBoard{
      hosted_board_id: "board-1",
      slug: "board-1",
      canonical_board_uri: "http://localhost:4001/boards/board-1",
      title: "Public fixture board"
    })

    :ok
  end

  defp get_json(path) do
    conn(:get, path) |> Router.call(@router_opts)
  end

  defp append_op(entity_type, entity_id, payload, opts \\ []) do
    {:ok, _log_id} =
      OpStore.append(%{
        op_id: Keyword.get(opts, :op_id, "op-#{System.unique_integer([:positive])}"),
        author_did: Keyword.get(opts, :author_did, "did:elix:author"),
        entity_type: entity_type,
        entity_id: entity_id,
        op_type: Keyword.get(opts, :op_type, "insert"),
        payload: Jason.encode!(payload),
        signature: "sig"
      })
  end

  defp seed_thread(thread_id, title) do
    append_op("thread", thread_id, %{
      "boardId" => "board-1",
      "threadId" => thread_id,
      "title" => title,
      "createdAt" => "2026-07-01T00:00:00Z"
    })
  end

  test "404s for an unknown thread" do
    response = get_json("/api/v1/forum-host/threads/nope/preview")
    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "thread_not_found"
  end

  test "serves title, author, reply count and first-reply excerpt" do
    seed_thread("t1", "我們在重建什麼樣的網路？")

    append_op("post", "p1", %{
      "boardId" => "board-1",
      "threadId" => "t1",
      "content" => "  便利往往是監控偽裝成的禮物。  ",
      "createdAt" => "2026-07-01T01:00:00Z"
    })

    append_op("post", "p2", %{
      "boardId" => "board-1",
      "threadId" => "t1",
      "content" => "第二則回應",
      "createdAt" => "2026-07-01T02:00:00Z"
    })

    # A post in another thread must not count.
    append_op("post", "p3", %{
      "boardId" => "board-1",
      "threadId" => "t-other",
      "content" => "別串的回應"
    })

    response = get_json("/api/v1/forum-host/threads/t1/preview")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["thread_id"] == "t1"
    assert body["board_id"] == "board-1"
    assert body["title"] == "我們在重建什麼樣的網路？"
    assert body["author_did"] == "did:elix:author"
    assert Map.has_key?(body, "author_handle")
    assert body["reply_count"] == 2
    assert body["excerpt"] == "便利往往是監控偽裝成的禮物。"
    assert body["locked"] == false
  end

  test "long first replies are truncated to a 200-char excerpt" do
    seed_thread("t-long", "Long thread")
    long = String.duplicate("a", 300)

    append_op("post", "p-long", %{
      "boardId" => "board-1",
      "threadId" => "t-long",
      "content" => long
    })

    response = get_json("/api/v1/forum-host/threads/t-long/preview")
    body = Jason.decode!(response.resp_body)
    assert String.length(body["excerpt"]) == 201
    assert String.ends_with?(body["excerpt"], "…")
  end

  test "a moderation-removed thread 404s with the public reason code" do
    seed_thread("t-removed", "Removed thread")

    Repo.insert!(%ForumHostModerationAction{
      action: "remove_post_from_board",
      target_ref: "t-removed",
      board_id: "board-1",
      moderator_did: "did:elix:mod",
      reason_code: "spam"
    })

    response = get_json("/api/v1/forum-host/threads/t-removed/preview")
    assert response.status == 404

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "thread_removed"
    assert body["reason_code"] == "spam"
  end
end
