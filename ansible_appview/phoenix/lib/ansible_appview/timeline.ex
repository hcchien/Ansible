defmodule AnsibleAppview.Timeline do
  @moduledoc """
  Fan-out-on-read timeline queries over the `feed_items` projection. Returns only
  non-deleted, public/unlisted items, newest first, paginated by relay `log_id`.
  Each item carries `public_key_hex` so the client can re-verify.
  """

  import Ecto.Query
  alias AnsibleAppview.Repo
  alias AnsibleAppview.Db.FeedItem

  @relayable ~w(public unlisted)

  @spec for_authors([String.t()], integer() | nil, pos_integer()) :: map()
  def for_authors(dids, cursor, limit) when is_list(dids) do
    page(from(f in FeedItem, where: f.author_did in ^dids), cursor, limit)
  end

  @spec for_board(String.t(), integer() | nil, pos_integer()) :: map()
  def for_board(board_id, cursor, limit) do
    page(from(f in FeedItem, where: f.board_id == ^board_id), cursor, limit)
  end

  defp page(query, cursor, limit) do
    limit = limit |> min(200) |> max(1)

    base =
      from f in query,
        where:
          f.deleted == false and
            (is_nil(f.visibility) or f.visibility in ^@relayable),
        order_by: [desc: f.log_id],
        limit: ^(limit + 1)

    scoped =
      if is_integer(cursor) and cursor > 0 do
        from f in base, where: f.log_id < ^cursor
      else
        base
      end

    rows = Repo.all(scoped)
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

  defp to_map(%FeedItem{} = f) do
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
