defmodule AnsibleRelay.ForumHost.PostingGateTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Db.ForumHostBoard
  alias AnsibleRelay.ForumHost.PostingGate
  alias AnsibleRelay.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "resolves app composite board references by their canonical numeric id" do
    hosted_board_id = "2026-#{System.unique_integer([:positive])}"

    board =
      Repo.insert!(%ForumHostBoard{
        hosted_board_id: hosted_board_id,
        slug: hosted_board_id,
        canonical_board_uri: "https://relay.example/boards/#{hosted_board_id}",
        title: "Capability-gated board"
      })

    composite_id = "178597971777_#{board.board_id}"

    assert %ForumHostBoard{board_id: board_id} = PostingGate.get_board(composite_id)
    assert board_id == board.board_id
  end

  test "does not accept a partial canonical id in an app composite reference" do
    hosted_board_id = "2026-#{System.unique_integer([:positive])}"

    board =
      Repo.insert!(%ForumHostBoard{
        hosted_board_id: hosted_board_id,
        slug: hosted_board_id,
        canonical_board_uri: "https://relay.example/boards/#{hosted_board_id}",
        title: "Capability-gated board"
      })

    assert nil == PostingGate.get_board("178597971777_#{board.board_id}x")
  end
end
