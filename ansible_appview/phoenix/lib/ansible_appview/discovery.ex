defmodule AnsibleAppview.Discovery do
  @moduledoc """
  Read-side discovery so clients are not isolated islands. Powered entirely by the
  existing read model (the follow graph + `feed_items`); no new firehose data.

  - `suggested_follows/2` — who to follow: globally popular authors plus
    friends-of-friends (followed by people the reader already follows), excluding
    the reader and everyone they already follow.
  - `explore/2` — a global, newest-first feed of public content, so a brand-new
    account with zero follows still has something to read.

  Privacy: only public/unlisted, non-deleted content is ever surfaced (same gate
  as the timeline). Abuse-resistance: results carry `author_tier` so callers can
  rank verified authors up and spam tiers down.
  """

  import Ecto.Query

  alias AnsibleAppview.{FollowGraph, Profiles, Repo, Timeline}
  alias AnsibleAppview.Db.{FeedItem, Follow}

  @relayable ~w(public unlisted)
  @explore_types ~w(murmur note post)

  # A friend-of-friend edge is worth this many global followers when ranking
  # suggestions — strong social proof beats raw popularity.
  @mutual_weight 50

  defp read_repo, do: Application.get_env(:ansible_appview, :read_repo, Repo)

  @doc """
  Suggests up to `limit` accounts for `reader_did` to follow. Returns a list of
  `%{did, follower_count, mutual_count, reason}` ordered by a popularity +
  social-proof score.
  """
  @spec suggested_follows(String.t(), pos_integer()) :: [map()]
  def suggested_follows(reader_did, limit \\ 20) when is_binary(reader_did) do
    limit = limit |> min(100) |> max(1)

    following = FollowGraph.following(reader_did)
    exclude = MapSet.new([reader_did | following])

    # Friends-of-friends: authors followed by the people the reader follows,
    # with how many of the reader's followees follow each (the mutual count).
    fof_counts =
      case following do
        [] ->
          %{}

        _ ->
          read_repo().all(
            from f in Follow,
              where: f.follower_did in ^following,
              group_by: f.author_did,
              select: {f.author_did, count(f.follower_did)}
          )
          |> Map.new()
      end

    # Globally popular authors (cap the scan; we only need a ranked shortlist).
    popular =
      read_repo().all(
        from f in Follow,
          group_by: f.author_did,
          select: f.author_did,
          order_by: [desc: count(f.follower_did)],
          limit: ^(limit * 5)
      )

    candidates =
      (Map.keys(fof_counts) ++ popular)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(exclude, &1))

    follower_counts = FollowGraph.follower_counts(candidates)

    candidates
    |> Enum.map(fn did ->
      followers = Map.get(follower_counts, did, 0)
      mutuals = Map.get(fof_counts, did, 0)

      %{
        did: did,
        follower_count: followers,
        mutual_count: mutuals,
        reason: if(mutuals > 0, do: "followed_by_people_you_follow", else: "popular"),
        score: followers + mutuals * @mutual_weight
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :score))
  end

  @doc """
  Global newest-first feed of public content (the "explore" tab). Paginated by
  `log_id` like the timeline.
  """
  @spec explore(integer() | nil, pos_integer()) :: map()
  def explore(cursor, limit) do
    limit = limit |> min(100) |> max(1)

    base =
      from f in FeedItem,
        where:
          f.deleted == false and f.entity_type in ^@explore_types and
            (is_nil(f.visibility) or f.visibility in ^@relayable),
        order_by: [desc: f.log_id],
        limit: ^(limit + 1)

    scoped =
      if is_integer(cursor) and cursor > 0 do
        from f in base, where: f.log_id < ^cursor
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
      items: Enum.map(visible, &Timeline.to_map/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc """
  Unified search across actors (profiles) and posts (content). Substring match
  via trigram-indexed ILIKE so it works for both Chinese and Latin text. Returns
  `%{actors: [...], posts: [...]}`; only public content is searched.
  """
  @spec search(String.t(), pos_integer()) :: map()
  def search(query, limit \\ 20) when is_binary(query) do
    q = query |> String.trim() |> String.downcase()
    limit = limit |> min(50) |> max(1)

    if q == "" do
      %{actors: [], posts: []}
    else
      %{actors: Profiles.search(query, limit), posts: search_posts(q, limit)}
    end
  end

  defp search_posts(q, limit) do
    like = "%" <> escape_like(q) <> "%"

    read_repo().all(
      from f in FeedItem,
        where:
          f.deleted == false and f.entity_type in ^@explore_types and
            (is_nil(f.visibility) or f.visibility in ^@relayable) and
            fragment("search_text LIKE ?", ^like),
        order_by: [desc: f.log_id],
        limit: ^limit
    )
    |> Enum.map(&Timeline.to_map/1)
  end

  # Escape LIKE wildcards so literal % / _ in the query can't widen the match.
  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
