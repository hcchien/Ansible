defmodule AnsibleRelay.PublicReadsTest do
  use ExUnit.Case, async: false
  use Plug.Test
  alias AnsibleRelay.{Repo, OpStore, IdentityCache, PublicReads}
  alias AnsibleRelay.Web.Router

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    did = "did:key:z-public-#{System.unique_integer([:positive])}"
    IdentityCache.put(did, String.duplicate("ab", 32), "public-read-test")
    %{did: did}
  end

  defp append(did, id, payload, opts \\ []) do
    op = %{
      op_id: "op-#{System.unique_integer([:positive])}",
      author_did: did,
      entity_type: opts[:type] || "murmur",
      entity_id: id,
      op_type: opts[:op] || "insert",
      payload: Base.encode64(Jason.encode!(payload)),
      signature: "accepted-at-ingest",
      received_at: "2026-09-14T00:00:00Z"
    }

    assert {:ok, log} = OpStore.append(op)
    log
  end

  test "only public latest revisions surface, preserving publication time and proof", %{did: did} do
    append(did, "a", %{
      "visibility" => "public",
      "body" => "old",
      "createdAt" => "2026-09-01T00:00:00Z"
    })

    append(
      did,
      "a",
      %{"visibility" => "public", "body" => "edited", "createdAt" => "2026-09-01T00:00:00Z"},
      op: "update"
    )

    append(did, "b", %{"visibility" => "private", "body" => "secret"})
    append(did, "c", %{"visibility" => "followers", "body" => "restricted"})
    append(did, "d", %{"visibility" => "unlisted", "body" => "unlisted"})
    append(did, "e", %{"visibility" => "public", "body" => "deleted"})
    append(did, "e", %{}, op: "delete")
    assert %{items: [item]} = PublicReads.explore(%{})
    assert item.entity_id == "a"
    assert item.payload["body"] == "edited"
    assert item.created_at == "2026-09-01T00:00:00Z"
    assert item.signature == "accepted-at-ingest"
    assert Base.decode64!(item.signed_payload) =~ "edited"
    assert {:ok, _} = PublicReads.content("murmur", "d")
    assert {:error, :deleted} = PublicReads.content("murmur", "e")
  end

  test "visibility updates hide old public versions; unrelated authors cannot replace them", %{
    did: did
  } do
    append(did, "a", %{"visibility" => "public", "body" => "public"})
    append(did, "a", %{"visibility" => "followers", "body" => "private revision"}, op: "update")
    append(did, "b", %{"visibility" => "public", "body" => "original"})
    append("did:key:attacker", "b", %{"visibility" => "public", "body" => "forged"}, op: "update")
    assert PublicReads.explore(%{}).items == []
    assert PublicReads.search(%{"q" => "public"}).posts == []
  end

  test "unknown boards and replies to private content fail closed", %{did: did} do
    append(did, "t", %{"boardId" => "unknown", "title" => "protected"}, type: "thread")
    append(did, "p", %{"visibility" => "private", "body" => "private"})
    append(did, "c", %{"threadId" => "p", "content" => "private reply"}, type: "comment")
    assert PublicReads.thread("p", %{}).items == []
    assert PublicReads.explore(%{}).items == []
  end

  test "cursor advances over filtered rows and never duplicates latest content", %{did: did} do
    for id <- 1..5,
        do:
          append(did, "item-#{id}", %{
            "visibility" => if(id == 4, do: "private", else: "public"),
            "body" => "#{id}"
          })

    first = PublicReads.explore(%{"limit" => "2"})
    assert first.has_more
    assert length(first.items) == 1
    second = PublicReads.explore(%{"limit" => "2", "cursor" => first.next_cursor})
    third = PublicReads.explore(%{"limit" => "2", "cursor" => second.next_cursor})

    assert Enum.map(first.items ++ second.items ++ third.items, & &1.entity_id) == [
             "item-5",
             "item-3",
             "item-2",
             "item-1"
           ]

    refute third.has_more
  end

  test "partial edits preserve intermediate changes and author time", %{did: did} do
    append(
      did,
      "n",
      %{
        "visibility" => "public",
        "title" => "first",
        "body" => "original",
        "createdAt" => "2026-08-01T00:00:00Z"
      },
      type: "note"
    )

    append(did, "n", %{"title" => "second"}, type: "note", op: "update")
    append(did, "n", %{"body" => "third"}, type: "note", op: "update")
    assert {:ok, item} = PublicReads.content("note", "n")
    assert item.payload["title"] == "second"
    assert item.payload["body"] == "third"
    assert item.created_at == "2026-08-01T00:00:00Z"
    assert Base.decode64!(item.signed_payload) == Jason.encode!(%{"body" => "third"})
  end

  test "board access and parent deletion gate comments even with explicit board metadata", %{
    did: did
  } do
    board =
      Repo.insert!(%AnsibleRelay.Db.ForumHostBoard{
        hosted_board_id: "public-read-board",
        slug: "public-read-board",
        canonical_board_uri: "https://relay.example/boards/test",
        title: "Public",
        content_visibility: "public",
        access_policy: %{"read" => %{"requirement" => "public"}}
      })

    board_id = "178597971777_#{board.board_id}"
    append(did, "t", %{"boardId" => board_id, "title" => "Thread"}, type: "thread")

    append(did, "p", %{"boardId" => board_id, "threadId" => "t", "content" => "Opening"},
      type: "post"
    )

    assert {:ok, post} = PublicReads.content("post", "p")
    assert post.board_id == to_string(board.board_id)
    assert post.payload["threadTitle"] == "Thread"
    append(did, "t", %{}, type: "thread", op: "delete")
    assert PublicReads.thread("t", %{}).items == []

    Repo.update!(
      Ecto.Changeset.change(board, access_policy: %{"read" => %{"requirement" => "credential"}})
    )

    assert PublicReads.explore(%{}).items == []
  end

  test "public reactions and comments supply existing timeline count contract", %{did: did} do
    append(did, "m", %{"visibility" => "public", "body" => "Hello"})

    append(did, "c", %{"targetId" => "m", "threadId" => "m", "content" => "Reply"},
      type: "comment"
    )

    append(did, "r", %{"targetId" => "m", "reactionType" => "like"}, type: "reaction")
    assert {:ok, item} = PublicReads.content("murmur", "m")
    assert item.comment_count == 1
    assert item.reaction_count == 1

    append(did, "reply-reaction", %{"targetId" => "c", "reactionType" => "happy"},
      type: "reaction"
    )

    assert Enum.any?(PublicReads.thread("m", %{}).items, &(&1.entity_id == "reply-reaction"))
    append(did, "r", %{}, type: "reaction", op: "delete")
    assert {:ok, %{reaction_count: 0}} = PublicReads.content("murmur", "m")
  end

  test "anonymous query contract rejects unbounded or invalid author lists" do
    conn =
      conn(:post, "/api/v1/timeline", Jason.encode!(%{"dids" => "all"}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(Router.init([]))

    assert conn.status == 422
  end

  test "external lane requires an allowed public board and rechecks latest visibility" do
    board =
      Repo.insert!(%AnsibleRelay.Db.ForumHostBoard{
        hosted_board_id: "external-read-board",
        slug: "external-read-board",
        canonical_board_uri: "https://relay.example/boards/external",
        title: "External",
        content_visibility: "public",
        access_policy: %{"read" => %{"requirement" => "public"}},
        posting_policy: %{"external_inclusion" => true}
      })

    actor = "https://remote.example/users/a"
    previous = Application.get_env(:ansible_relay, :external_sources)

    Application.put_env(:ansible_relay, :external_sources, [
      %{board_id: board.hosted_board_id, actor_uri: actor}
    ])

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:ansible_relay, :external_sources),
        else: Application.put_env(:ansible_relay, :external_sources, previous)
    end)

    insert = fn type, object, audience ->
      Repo.insert!(%AnsibleRelay.Db.ActivityPubInboundActivity{
        activity_id: "https://remote.example/activity/#{System.unique_integer([:positive])}",
        local_actor: "https://relay.example/actor",
        remote_actor: actor,
        activity_type: type,
        object_id: "https://remote.example/post/1",
        payload: %{"type" => type, "to" => audience, "object" => object},
        received_at: DateTime.utc_now()
      })
    end

    object = %{"id" => "https://remote.example/post/1", "content" => "Public text"}
    insert.("Create", object, ["https://www.w3.org/ns/activitystreams#Public"])
    assert [item] = AnsibleRelay.PublicExternalReads.for_board(board.hosted_board_id, %{}).items
    assert item.reputation_tier == "external_unverified"
    refute item.sig_verified
    insert.("Update", object, ["https://remote.example/followers"])
    assert AnsibleRelay.PublicExternalReads.for_board(board.hosted_board_id, %{}).items == []
    insert.("Update", object, ["https://www.w3.org/ns/activitystreams#Public"])

    Repo.update!(
      Ecto.Changeset.change(board, access_policy: %{"read" => %{"requirement" => "credential"}})
    )

    assert AnsibleRelay.PublicExternalReads.for_board(board.hosted_board_id, %{}).items == []
  end
end
