defmodule AnsibleAppview.External do
  @moduledoc """
  The per-board external read lane (inbound federation, design 2026-06-13 D3/D4,
  Task 4b-1).

  This is the **only** read path that returns external (`source = "activitypub"`)
  content. Every other AppView read (`Timeline`, `Discovery`) requires
  `sig_verified == true`, and external items are written with
  `sig_verified = false` / `author_tier = "external_unverified"`, so they are
  excluded from those surfaces by construction. This module deliberately does NOT
  apply the `sig_verified` filter — it is the dedicated, honestly-labeled lane —
  but it constrains itself to `source == "activitypub"` so it can never surface a
  native verified row.

  ## Per-board mapping

  A curated `ExternalSource` is mapped to one Elix board (`external_sources.board_id`).
  Ingest stamps that `board_id` onto each external `feed_items` row, so a board's
  external feed is a simple `(board_id, source == "activitypub")` filter. A board
  with no mapped sources returns an empty page.

  ## Gating boundary (who enforces external_inclusion AND user opt-in)

  This module serves the lane unconditionally; it does **not** decide whether the
  lane should be shown. Per design D4, effective visibility =
  `board.external_inclusion (relay forum-host policy) AND user-allows-external
  (per-user opt-in, conservative default)`. Both knobs live OUTSIDE the AppView:
  the board-level `external_inclusion` policy is enforced at the relay
  forum-host's policy-set chokepoint (also mutually exclusive with 真人版
  `min_post_tier`), and the per-user opt-in / global hide-all-external toggle live
  at the client. **The CALLER is responsible for only invoking this endpoint when
  both gates allow it.** The AppView serves the data lane; the policy/consent
  gating is not its job.
  """

  import Ecto.Query

  alias AnsibleAppview.Db.FeedItem

  @source "activitypub"

  defp read_repo, do: Application.get_env(:ansible_appview, :read_repo, AnsibleAppview.Repo)

  @doc """
  External feed items mapped to `board_id`, newest-first, paginated.

  Returns `%{items: [...], next_cursor: integer | nil, has_more: boolean}` where
  each item carries `external_actor_uri`, `external_instance`, `compliance_level`,
  `content`, `created_at`, plus `external: true` and `origin: "activitypub"` so
  clients can badge it. Only `source == "activitypub"` rows for this exact board
  are returned; a board with no mapped/ingested external content returns `[]`.

  Pagination mirrors the other feed endpoints (opaque integer cursor). External
  rows use synthetic NEGATIVE, monotonically-decreasing `log_id`s, so newest-first
  is `log_id ASC` and the next page is rows with `log_id > cursor`.
  """
  @spec for_board(String.t(), integer() | nil, pos_integer()) :: map()
  def for_board(board_id, cursor, limit) when is_binary(board_id) do
    limit = limit |> min(200) |> max(1)

    base =
      from(f in FeedItem,
        where: f.board_id == ^board_id and f.source == ^@source and f.deleted == false,
        order_by: [asc: f.log_id],
        limit: ^(limit + 1)
      )

    scoped =
      if is_integer(cursor) do
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

    %{
      items: Enum.map(visible, &to_map/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc "Presents an external FeedItem row as the per-board external read item map."
  def to_map(%FeedItem{} = f) do
    %{
      log_id: f.log_id,
      op_id: f.op_id,
      board_id: f.board_id,
      entity_type: f.entity_type,
      content: f.payload && f.payload["content"],
      created_at: f.item_created_at && DateTime.to_iso8601(f.item_created_at),
      external_actor_uri: f.external_actor_uri,
      external_instance: f.external_instance,
      compliance_level: f.compliance_level,
      reputation_tier: f.author_tier,
      # Explicit origin markers so clients badge external content unmistakably
      # (Constitution Base Rules 6/7: external origin must always be visible).
      external: true,
      origin: f.source
    }
  end
end
