defmodule AnsibleAppview.Repo.Migrations.AddFeedItemsThreadIdIndex do
  use Ecto.Migration

  @moduledoc """
  `Timeline.for_thread/3` (GET /api/v1/thread/:thread_id) filters
  `thread_id = ? ORDER BY log_id`, but no existing index covers `thread_id`
  (existing indexes cover op_id, author_did+log_id, board_id+log_id,
  board_id+source, external_actor_uri). A composite `(thread_id, log_id)` index
  lets Postgres both filter and satisfy the ordering without a sort.
  """

  def change do
    create index(:feed_items, [:thread_id, :log_id])
  end
end
