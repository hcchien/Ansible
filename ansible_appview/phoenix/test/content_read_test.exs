defmodule AnsibleAppview.ContentReadTest do
  use ExUnit.Case, async: false
  alias AnsibleAppview.{Repo, Timeline, Db.FeedItem}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "exact standalone reads are verified, public and latest-state only" do
    row =
      Repo.insert!(%FeedItem{
        log_id: 99001,
        op_id: "exact-1",
        entity_id: "n1",
        entity_type: "note",
        op_type: "insert",
        author_did: "did:key:a",
        visibility: "public",
        sig_verified: true,
        deleted: false,
        payload: %{"body" => "full content"}
      })

    assert {:ok, %{entity_id: "n1", sig_verified: true}} = Timeline.content("note", "n1")
    row = Repo.update!(Ecto.Changeset.change(row, visibility: "private"))
    assert {:error, :not_found} = Timeline.content("note", "n1")
    row = Repo.update!(Ecto.Changeset.change(row, visibility: "public", sig_verified: false))
    assert {:error, :not_found} = Timeline.content("note", "n1")
    Repo.update!(Ecto.Changeset.change(row, visibility: "public", deleted: true))
    assert {:error, :deleted} = Timeline.content("note", "n1")
  end
end
