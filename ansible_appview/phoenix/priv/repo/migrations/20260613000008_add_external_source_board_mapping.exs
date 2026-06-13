defmodule AnsibleAppview.Repo.Migrations.AddExternalSourceBoardMapping do
  use Ecto.Migration

  # Inbound federation — Task 4b-1 read contract (design 2026-06-13, D3/D4).
  #
  # Maps a curated external source to the Elix board its content surfaces in.
  # `board_id` is the Elix board this source feeds; NULL means the source is
  # ingested but not surfaced to any board (still off ALL verified reads via the
  # Phase 2 `sig_verified` filter).
  #
  # Ingest stamps this `board_id` onto every external `feed_items` row it writes
  # (feed_items already has a `board_id` column used by native rows), so the
  # per-board external read endpoint is a simple `board_id` + `source` filter.
  def change do
    alter table(:external_sources) do
      add(:board_id, :string)
    end

    # Per-board external reads filter feed_items on (board_id, source); index the
    # source column's board_id too so listing sources for a board is cheap.
    create(index(:external_sources, [:board_id]))
    create(index(:feed_items, [:board_id, :source]))
  end
end
