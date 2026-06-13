defmodule AnsibleAppview.Repo.Migrations.AddExternalFederationLane do
  use Ecto.Migration

  # Inbound federation — curated ActivityPub ingest (design 2026-06-13).
  #
  # Two pieces of the "external lane" that keeps foreign AP content OUT of the
  # verified surfaces by construction:
  #
  #   1. `external_sources` — the admin-curated allowlist of remote AP actors we
  #      choose to pull. Removing/disabling a row is the reversibility lever
  #      (Constitution Base Rule 7): its content can then be filtered out.
  #   2. `feed_items` provenance columns for ingested external items
  #      (`external_actor_uri`, `external_instance`, `compliance_level`). NULL for
  #      native relay-folded rows. External rows are written with
  #      `sig_verified=false` / `author_tier="external_unverified"`, so the Phase 2
  #      read filter (`sig_verified == true`) already excludes them everywhere.
  def change do
    create table(:external_sources, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:actor_uri, :string, null: false)
      add(:instance, :string, null: false)
      add(:display_name, :string)
      # compliance_level: "compatible" (assessed allowlisted instance) |
      # "unknown" (un-assessed; lower-ranked). Never implies Elix trust.
      add(:compliance_level, :string, null: false, default: "unknown")
      add(:enabled, :boolean, null: false, default: true)
      add(:last_polled_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:external_sources, [:actor_uri], name: :external_sources_actor_uri_index))
    create(index(:external_sources, [:enabled]))

    alter table(:feed_items) do
      # Provenance for the external lane. NULL on native (relay_firehose) rows.
      add(:external_actor_uri, :string)
      add(:external_instance, :string)
      add(:compliance_level, :string)
    end

    # Filter external rows by their originating actor (reversibility: a disabled/
    # removed source's content can be excluded by actor_uri).
    create(index(:feed_items, [:external_actor_uri]))

    # External items have no relay `log_id` but feed_items.log_id is a NOT NULL
    # primary key. Allocate synthetic NEGATIVE log_ids from a dedicated sequence
    # so they are unique and can never collide with the positive, monotonically
    # increasing relay log_ids. Dedup is keyed on `op_id` (= AP object id), not
    # log_id, so a re-poll never inserts a second row.
    execute(
      "CREATE SEQUENCE IF NOT EXISTS external_feed_log_seq START WITH -1 INCREMENT BY -1 MINVALUE -9223372036854775808 MAXVALUE -1 NO CYCLE",
      "DROP SEQUENCE IF EXISTS external_feed_log_seq"
    )
  end
end
