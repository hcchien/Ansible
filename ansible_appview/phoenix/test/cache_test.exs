defmodule AnsibleAppview.CacheTest do
  use ExUnit.Case, async: false

  alias AnsibleAppview.Cache

  test "ETS adapter stores, reads, and expires entries" do
    key = "test:#{System.unique_integer([:positive])}"
    assert Cache.get(key) == :miss

    :ok = Cache.put(key, [1, 2, 3], 5_000)
    assert Cache.get(key) == {:ok, [1, 2, 3]}

    # Already-expired entry reads as a miss.
    expired = "test:#{System.unique_integer([:positive])}"
    :ok = Cache.put(expired, :gone, 0)
    Process.sleep(2)
    assert Cache.get(expired) == :miss
  end
end
