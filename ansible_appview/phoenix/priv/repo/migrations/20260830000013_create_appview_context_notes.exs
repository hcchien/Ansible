defmodule AnsibleAppview.Repo.Migrations.CreateAppviewContextNotes do
  use Ecto.Migration

  def change do
    create table(:appview_context_notes, primary_key: false) do
      add(:note_id, :text, primary_key: true)
      add(:author_did, :text, null: false)
      add(:canonical_author_did, :text, null: false)
      add(:target_entity_type, :text, null: false)
      add(:target_entity_id, :text, null: false)
      add(:target_op_id, :text, null: false)
      add(:target_content_hash, :text, null: false)
      add(:body, :text, null: false)
      add(:sources, {:array, :map}, null: false, default: [])
      add(:board_id, :text)
      add(:created_at, :utc_datetime_usec)
      add(:updated_log_id, :bigint, null: false)
      add(:source, :text, null: false)
      add(:signature, :text, null: false)
      add(:public_key_hex, :text)
      add(:verified_at, :utc_datetime_usec, null: false)
      add(:anchor_expires_at, :utc_datetime_usec)
      add(:deleted, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:appview_context_notes, [:target_entity_id, :deleted]))
    create(index(:appview_context_notes, [:target_entity_type, :target_entity_id]))
    create(index(:appview_context_notes, [:updated_log_id]))
  end
end
