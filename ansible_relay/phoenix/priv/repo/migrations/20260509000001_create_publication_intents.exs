defmodule AnsibleRelay.Repo.Migrations.CreatePublicationIntents do
  use Ecto.Migration

  def change do
    create table(:publication_intents) do
      add(:publication_id, :string, null: false)
      add(:intent_id, :string, null: false)
      add(:author_did, :string, null: false)
      add(:content_item_id, :string, null: false)
      add(:action, :string, null: false)
      add(:visibility, :string, null: false)
      add(:payload, :map)
      add(:payload_hash, :string, null: false)
      add(:signature, :string, null: false)
      add(:signature_scheme, :string, null: false)
      add(:status, :string, null: false)
      add(:delivery_status, :string, null: false)
      add(:received_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:publication_intents, [:publication_id],
        name: :publication_intents_publication_id_index
      )
    )

    create(
      unique_index(:publication_intents, [:intent_id], name: :publication_intents_intent_id_index)
    )

    create(index(:publication_intents, [:author_did]))
    create(index(:publication_intents, [:content_item_id]))
    create(index(:publication_intents, [:delivery_status]))
  end
end
