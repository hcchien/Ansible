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

  test "periodic sweep deletes expired rows never read back" do
    # A key that is written but never re-read: only the sweep can reclaim it.
    key = "sweep:#{System.unique_integer([:positive])}"
    :ok = Cache.put(key, :dead, 0)
    Process.sleep(2)

    removed = AnsibleAppview.Cache.ETS.sweep_expired()
    assert removed >= 1

    # The underlying row is gone (not just lazily hidden on read).
    assert :ets.lookup(:ansible_appview_cache, key) == []
  end
end
