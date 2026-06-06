defmodule AnsibleAppview.HomeTimelineTest do
  use ExUnit.Case, async: false

  alias AnsibleAppview.HomeTimeline

  test "ETS adapter adds, ranges newest-first, paginates by cursor, and caps" do
    reader = "did:key:reader#{System.unique_integer([:positive])}"

    HomeTimeline.add_many([
      {reader, 10, "op-10"},
      {reader, 20, "op-20"},
      {reader, 30, "op-30"}
    ])
    # An entry for a different reader must not leak in.
    HomeTimeline.add("did:key:other", 25, "op-other")

    assert HomeTimeline.exists?(reader)

    page = HomeTimeline.range(reader, nil, 2)
    assert Enum.map(page, & &1.op_id) == ["op-30", "op-20"]
    assert Enum.map(page, & &1.log_id) == [30, 20]

    # Cursor pagination (strictly older than cursor).
    next = HomeTimeline.range(reader, 20, 10)
    assert Enum.map(next, & &1.op_id) == ["op-10"]

    # Cap keeps the newest N.
    :ok = HomeTimeline.cap(reader, 2)
    capped = HomeTimeline.range(reader, nil, 10)
    assert Enum.map(capped, & &1.op_id) == ["op-30", "op-20"]
  end

  test "exists? is false for an unknown reader" do
    refute HomeTimeline.exists?("did:key:nobody#{System.unique_integer([:positive])}")
  end
end
