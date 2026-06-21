defmodule AnsibleAppview.Timeline do
  @moduledoc """
  Fan-out-on-read timeline queries over the `feed_items` projection. Returns only
  non-deleted, public/unlisted, independently signature-verified
  (`sig_verified=true`) items, newest first, paginated by relay `log_id`. Each
  item carries `public_key_hex` so the client can re-verify.

  The `sig_verified` filter is defense-in-depth: the fold path already drops ops
  that fail independent verification, but every public read also excludes
  unverified rows so a row written by any other path can never surface.
  """

  import Ecto.Query
  alias AnsibleAppview.Db.FeedItem

  defp read_repo, do: Application.get_env(:ansible_appview, :read_repo, AnsibleAppview.Repo)

  @relayable ~w(public unlisted)

  @doc """
  Personalized home timeline for one reader (fan-out-on-write read path).

  Reads `{log_id, op_id}` references from the materialized `HomeTimeline`, hydrates
  them through the `item:{op_id}` object cache (MGET-style; DB fallback on miss),
  then merges in recent items from followed celebrities (skipped on write). If the
  reader has no materialized timeline yet (cold), falls back to fan-out-on-read
  over the reader's follow graph so the first request is never empty.
  """
  @spec home(String.t(), integer() | nil, pos_integer()) :: map()
  def home(reader_did, cursor, limit) when is_binary(reader_did) do
    limit = limit |> min(200) |> max(1)
    entries = AnsibleAppview.HomeTimeline.range(reader_did, cursor, limit)

    if entries == [] and not AnsibleAppview.HomeTimeline.exists?(reader_did) do
      # Cold reader: rebuild-on-read from the follow graph.
      following = AnsibleAppview.FollowGraph.following(reader_did)
      for_authors(following, cursor, limit)
    else
      fanned = hydrate(entries)

      following = AnsibleAppview.FollowGraph.following(reader_did)
      threshold = Application.get_env(:ansible_appview, :celebrity_follower_threshold, 10_000)

      celeb_items =
        following
        |> AnsibleAppview.FollowGraph.celebrities(threshold)
        |> Enum.flat_map(&author_recent/1)
        |> Enum.filter(fn it -> is_nil(cursor) or cursor <= 0 or it.log_id < cursor end)

      merged =
        (fanned ++ celeb_items)
        |> Enum.uniq_by(& &1.op_id)
        |> Enum.sort_by(& &1.log_id, :desc)
        |> Enum.take(limit)

      next_cursor =
        case merged do
          [] -> nil
          list -> List.last(list).log_id
        end

      %{items: merged, next_cursor: next_cursor, has_more: length(merged) >= limit}
    end
  end

  # Resolve home-timeline references to full items via the object cache, falling
  # back to a single batched DB read for misses (and warming the cache).
  defp hydrate([]), do: []

  defp hydrate(entries) do
    {hits, misses} =
      Enum.reduce(entries, {[], []}, fn e, {hits, misses} ->
        case AnsibleAppview.Cache.get("item:" <> e.op_id) do
          {:ok, :deleted} -> {hits, misses}
          {:ok, item} -> {[item | hits], misses}
          :miss -> {hits, [e.op_id | misses]}
        end
      end)

    fetched =
      case misses do
        [] ->
          []

        ids ->
          ttl = Application.get_env(:ansible_appview, :item_cache_ttl_ms, 30_000)

          read_repo().all(
            from(f in FeedItem,
              where:
                f.op_id in ^ids and f.deleted == false and f.sig_verified == true and
                  (is_nil(f.visibility) or f.visibility in ^@relayable)
            )
          )
          |> Enum.map(fn f ->
            item = to_map(f)
            AnsibleAppview.Cache.put("item:" <> f.op_id, item, ttl)
            item
          end)
      end

    hits ++ fetched
  end

  @spec for_authors([String.t()], integer() | nil, pos_integer()) :: map()
  def for_authors(dids, cursor, limit) when is_list(dids) do
    # First page (no cursor) is served from the per-author building-block cache;
    # deeper pages fall through to a direct cursor query (cold path).
    if is_nil(cursor) or cursor <= 0 do
      cached_first_page(dids, limit)
    else
      page(from(f in FeedItem, where: f.author_did in ^dids), cursor, limit)
    end
  end

  defp cached_first_page(dids, limit) do
    limit = limit |> min(200) |> max(1)

    merged =
      dids
      |> Enum.uniq()
      |> Enum.flat_map(&author_recent/1)
      |> Enum.sort_by(& &1.log_id, :desc)

    has_more = length(merged) > limit
    visible = Enum.take(merged, limit)

    next_cursor =
      case visible do
        [] -> nil
        list -> List.last(list).log_id
      end

    %{items: visible, next_cursor: next_cursor, has_more: has_more}
  end

  defp author_recent(did) do
    key = "author:" <> did

    case AnsibleAppview.Cache.get(key) do
      {:ok, items} ->
        items

      :miss ->
        cap = Application.get_env(:ansible_appview, :author_cache_limit, 100)

        items =
          read_repo().all(
            from(f in FeedItem,
              where:
                f.author_did == ^did and f.deleted == false and f.sig_verified == true and
                  (is_nil(f.visibility) or f.visibility in ^@relayable),
              order_by: [desc: f.log_id],
              limit: ^cap
            )
          )
          |> Enum.map(&to_map/1)

        ttl = Application.get_env(:ansible_appview, :author_cache_ttl_ms, 10_000)
        AnsibleAppview.Cache.put(key, items, ttl)
        items
    end
  end

  @spec for_board(String.t(), integer() | nil, pos_integer()) :: map()
  def for_board(board_id, cursor, limit) do
    page(from(f in FeedItem, where: f.board_id == ^board_id), cursor, limit)
  end

  @doc """
  Items belonging to a thread id. Used to read comments on standalone content
  (murmur/note): a comment is a `post` op whose `thread_id` is the content's
  entity id, so it threads under the content even though it has no board.
  """
  @spec for_thread(String.t(), integer() | nil, pos_integer()) :: map()
  def for_thread(thread_id, cursor, limit) do
    page(from(f in FeedItem, where: f.thread_id == ^thread_id), cursor, limit)
  end

  defp page(query, cursor, limit) do
    limit = limit |> min(200) |> max(1)

    base =
      from(f in query,
        where:
          f.deleted == false and f.sig_verified == true and
            (is_nil(f.visibility) or f.visibility in ^@relayable),
        order_by: [desc: f.log_id],
        limit: ^(limit + 1)
      )

    scoped =
      if is_integer(cursor) and cursor > 0 do
        from(f in base, where: f.log_id < ^cursor)
      else
        base
      end

    rows = read_repo().all(scoped)
    has_more = length(rows) > limit
    visible = Enum.take(rows, limit)

    next_cursor =
      case visible do
        [] -> nil
        list -> List.last(list).log_id
      end

    %{
      items: Enum.map(visible, &to_map/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc "Presents a FeedItem row as the public timeline/discovery item map."
  def to_map(%FeedItem{} = f) do
    %{
      log_id: f.log_id,
      op_id: f.op_id,
      author_did: f.author_did,
      entity_type: f.entity_type,
      entity_id: f.entity_id,
      op_type: f.op_type,
      board_id: f.board_id,
      thread_id: f.thread_id,
      visibility: f.visibility,
      created_at: f.item_created_at && DateTime.to_iso8601(f.item_created_at),
      payload: f.payload,
      public_key_hex: f.public_key_hex,
      reputation_tier: f.author_tier
    }
  end
end
