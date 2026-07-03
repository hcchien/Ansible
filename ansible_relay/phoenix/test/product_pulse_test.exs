defmodule AnsibleRelay.ProductPulseTest do
  @moduledoc """
  Constitutional measurement: aggregate-only activation/retention/board
  gauges. The key property under test besides the numbers: the rendered
  /metrics output carries NO per-user identifier — only window labels.
  """

  use ExUnit.Case, async: false

  alias AnsibleRelay.{Db.DidAccount, Db.Op, Metrics, ProductPulse, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp insert_op(author, received_at, opts \\ []) do
    board = Keyword.get(opts, :board, "board-genesis")
    entity_type = Keyword.get(opts, :entity_type, "post")

    Repo.insert!(%Op{
      op_id: "op-#{System.unique_integer([:positive])}",
      author_did: author,
      entity_type: entity_type,
      entity_id: "e-#{System.unique_integer([:positive])}",
      op_type: "insert",
      payload: Jason.encode!(%{"boardId" => board, "content" => "x"}),
      signature: "sig",
      received_at: received_at
    })
  end

  test "activation/retention/board gauges aggregate correctly" do
    now = DateTime.utc_now()
    days = fn n -> DateTime.add(now, -n * 86_400, :second) end

    Repo.insert!(%DidAccount{did: "did:elix:old", public_key_hex: "aa", handle: "old.x", registered_at: DateTime.utc_now(), expires_at: DateTime.add(DateTime.utc_now(), 86_400 * 365, :second)})
    Repo.insert!(%DidAccount{did: "did:elix:new", public_key_hex: "bb", handle: "new.x", registered_at: DateTime.utc_now(), expires_at: DateTime.add(DateTime.utc_now(), 86_400 * 365, :second)})

    # "old" first posted a month ago and again yesterday → returning.
    insert_op("did:elix:old", days.(30), board: "board-a")
    insert_op("did:elix:old", days.(1), board: "board-a")
    # "new" first posted 2 days ago → new author (activation).
    insert_op("did:elix:new", days.(2), board: "board-b")
    # A non-board op (murmur) must not count toward board activity.
    Repo.insert!(%Op{
      op_id: "op-murmur",
      author_did: "did:elix:new",
      entity_type: "murmur",
      entity_id: "m-1",
      op_type: "insert",
      payload: Jason.encode!(%{"text" => "hi", "visibility" => "public"}),
      signature: "sig",
      received_at: days.(1)
    })

    assert :ok = ProductPulse.sample()
    rendered = Metrics.render()

    assert rendered =~ ~s(elix_registered_dids 2)
    assert rendered =~ ~s(elix_active_authors{window="7d"} 2)
    assert rendered =~ ~s(elix_active_authors{window="28d"} 2)
    assert rendered =~ ~s(elix_active_boards{window="7d"} 2)
    assert rendered =~ ~s(elix_new_authors{window="7d"} 1)
    assert rendered =~ ~s(elix_returning_authors{window="7d"} 1)
  end

  test "rendered output never carries per-user identifiers" do
    insert_op("did:elix:secretperson", DateTime.utc_now())
    assert :ok = ProductPulse.sample()

    rendered = Metrics.render()
    refute rendered =~ "secretperson"
    refute rendered =~ "did:elix"
  end
end
