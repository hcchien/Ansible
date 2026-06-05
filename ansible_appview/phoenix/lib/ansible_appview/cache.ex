defmodule AnsibleAppview.Cache do
  @moduledoc """
  Building-block cache for the timeline read path. Caches each author's recent
  item list (shared across all followers, so a popular author is fetched once and
  served to everyone), so the personalized first page is assembled from cached
  per-author lists instead of an uncacheable cross-author DB scatter-gather.

  Pluggable adapter: in-process ETS by default (single instance), Redix when a
  Redis URL is configured (multiple AppView instances share the cache).
  """

  @callback get(key :: String.t()) :: {:ok, term()} | :miss
  @callback put(key :: String.t(), value :: term(), ttl_ms :: non_neg_integer()) :: :ok

  def get(key), do: adapter().get(key)
  def put(key, value, ttl_ms), do: adapter().put(key, value, ttl_ms)

  defp adapter do
    Application.get_env(:ansible_appview, :cache_adapter, AnsibleAppview.Cache.ETS)
  end
end
