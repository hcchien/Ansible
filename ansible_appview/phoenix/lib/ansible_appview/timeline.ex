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
  alias AnsibleAppview.Profiles

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
      |> authors_recent()
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

  # Batched cold-read: resolve the per-author recent list for many DIDs with a
  # single `author_did IN (...)` windowed query for the cache-miss set, instead
  # of one query per followed author. Cache-hit authors are served from the
  # per-author cache; missed authors are queried together, grouped, capped, and
  # each author's slice is written back under its own key (preserving the same
  # per-author 10s TTL as `author_recent/1`).
  defp authors_recent([]), do: []

  defp authors_recent(dids) do
    {hits, misses} =
      Enum.reduce(dids, {[], []}, fn did, {hits, misses} ->
        case AnsibleAppview.Cache.get("author:" <> did) do
          {:ok, items} -> {[items | hits], misses}
          :miss -> {hits, [did | misses]}
        end
      end)

    fetched =
      case misses do
        [] -> []
        ids -> batch_author_recent(ids)
      end

    List.flatten(hits) ++ fetched
  end

  # One windowed query over all missing authors: rank rows per author by log_id
  # desc and keep the top `cap` per author. Authors with no rows are cached as
  # an empty list so a repeat request within the TTL is a hit, not a re-query.
  defp batch_author_recent(dids) do
    cap = Application.get_env(:ansible_appview, :author_cache_limit, 100)
    ttl = Application.get_env(:ansible_appview, :author_cache_ttl_ms, 10_000)

    ranked =
      from(f in FeedItem,
        where:
          f.author_did in ^dids and f.deleted == false and f.sig_verified == true and
            f.entity_type != "comment" and
            (is_nil(f.visibility) or f.visibility in ^@relayable),
        select: %{
          log_id: f.log_id,
          rn:
            over(row_number(),
              partition_by: f.author_did,
              order_by: [desc: f.log_id]
            )
        }
      )

    # Rank in-DB, keep the top `cap` per author, then hydrate the surviving rows
    # in a single lookup by primary key (`log_id`), ordered newest-first.
    kept_ids =
      read_repo().all(
        from(r in subquery(ranked),
          where: r.rn <= ^cap,
          select: r.log_id
        )
      )

    grouped =
      case kept_ids do
        [] ->
          %{}

        ids ->
          read_repo().all(
            from(f in FeedItem, where: f.log_id in ^ids, order_by: [desc: f.log_id])
          )
          |> Enum.map(&to_map/1)
          |> Enum.group_by(& &1.author_did)
      end

    Enum.flat_map(dids, fn did ->
      items = Map.get(grouped, did, [])
      AnsibleAppview.Cache.put("author:" <> did, items, ttl)
      items
    end)
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
                  f.entity_type != "comment" and
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

  @spec for_board(String.t(), String.t() | nil, integer() | nil, pos_integer()) :: map()
  def for_board(board_id, legacy_board_id, cursor, limit) do
    legacy_namespaced_id =
      case legacy_board_id do
        value when is_binary(value) and value != "" -> "%\\_" <> escape_like(value)
        _ -> nil
      end

    board_scope =
      dynamic([f], f.board_id == ^board_id) |> maybe_legacy_board(legacy_board_id, legacy_namespaced_id)

    page(
      from(f in FeedItem,
        # Current publications use the hosted board id verbatim. Earlier
        # mobile clients persisted `<local-id>_<hosted-board-id>`, so retain
        # that explicitly delimited legacy form. The escaped underscore is a
        # literal separator, not SQL LIKE's one-character wildcard: otherwise
        # reading `2026` also includes `fifa2026`.
        where: ^board_scope
      ),
      cursor,
      limit
    )
  end

  defp maybe_legacy_board(scope, legacy_board_id, legacy_namespaced_id)
       when is_binary(legacy_board_id) and is_binary(legacy_namespaced_id) do
    dynamic([f], ^scope or f.board_id == ^legacy_board_id or like(f.board_id, ^legacy_namespaced_id))
  end

  defp maybe_legacy_board(scope, _legacy_board_id, _legacy_namespaced_id), do: scope

  @doc """
  Items belonging to a thread id. Used to read comments on standalone content
  (murmur/note): a comment is a `post` op whose `thread_id` is the content's
  entity id, so it threads under the content even though it has no board.
  """
  @spec for_thread(String.t(), integer() | nil, pos_integer()) :: map()
  def for_thread(thread_id, cursor, limit) do
    # Own query (not `page`): `page` excludes entity_type "comment" from the
    # top-level feeds, but a thread/content view is exactly where comments belong.
    limit = limit |> min(200) |> max(1)

    base =
      from(f in FeedItem,
        where:
          f.thread_id == ^thread_id and f.deleted == false and
            f.sig_verified == true and
            (is_nil(f.visibility) or f.visibility in ^@relayable),
        order_by: [asc: f.log_id],
        limit: ^(limit + 1)
      )

    scoped =
      if is_integer(cursor) and cursor > 0 do
        from(f in base, where: f.log_id > ^cursor)
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

    %{items: Enum.map(visible, &to_map/1), next_cursor: next_cursor, has_more: has_more}
  end

  defp page(query, cursor, limit) do
    limit = limit |> min(200) |> max(1)

    base =
      from(f in query,
        where:
          f.deleted == false and f.sig_verified == true and
            f.entity_type != "comment" and
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
      author_handle: author_handle(f.author_did),
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

  defp author_handle(did) when is_binary(did) do
    case Profiles.get(did) do
      %{handle: handle} when is_binary(handle) and handle != "" -> handle
      _ -> nil
    end
  end

  defp author_handle(_did), do: nil

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
