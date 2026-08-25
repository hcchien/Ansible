defmodule AnsibleRelay.ForumHost.PollsTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Db.{ForumHostBoard, Op}
  alias AnsibleRelay.ForumHost.Polls
  alias AnsibleRelay.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "finds a poll whose thread preserves an app composite board id" do
    hosted_board_id = "poll-board-#{System.unique_integer([:positive])}"

    board =
      Repo.insert!(%ForumHostBoard{
        hosted_board_id: hosted_board_id,
        slug: hosted_board_id,
        canonical_board_uri: "https://relay.example/boards/#{hosted_board_id}",
        title: "Poll board"
      })

    poll_id = "poll-thread-#{System.unique_integer([:positive])}"

    payload =
      Jason.encode!(%{
        "boardId" => "1785979771777_#{board.board_id}",
        "poll" => %{
          "options" => [
            %{"id" => "a", "label" => "A"},
            %{"id" => "b", "label" => "B"}
          ]
        }
      })
      |> Base.encode64()

    Repo.insert!(%Op{
      op_id: "poll-op-#{System.unique_integer([:positive])}",
      author_did: "did:elix:poll-test",
      entity_type: "thread",
      entity_id: poll_id,
      op_type: "insert",
      payload: payload,
      signature: "test-signature",
      received_at: DateTime.utc_now()
    })

    assert {:ok, %{poll_id: ^poll_id, options: options}} = Polls.results(board, poll_id)
    assert Enum.map(options, & &1.id) == ["a", "b"]
  end
end
