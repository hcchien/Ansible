defmodule AnsibleAppview.Repo.Migrations.AddFeedItemsEntityIdIndex do
  use Ecto.Migration

  @moduledoc """
  Deletions and host moderation removals hide content by (entity_id, author_did):
  `Folder.mark_deleted/1` runs `UPDATE feed_items SET deleted=true WHERE
  entity_id = ? AND author_did = ? AND deleted = false`. No existing index covers
  `entity_id`, so each delete would sequentially scan. A composite
  `(entity_id, author_did)` index makes the takedown a point lookup.
  """

  def change do
    create index(:feed_items, [:entity_id, :author_did])
  end
end
