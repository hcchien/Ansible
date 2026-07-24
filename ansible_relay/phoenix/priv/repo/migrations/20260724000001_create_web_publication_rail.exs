defmodule AnsibleRelay.Repo.Migrations.CreateWebPublicationRail do
  use Ecto.Migration

  def change do
    alter table(:webauthn_credentials) do
      add(:delegation_id, :text)
      add(:credential_thumbprint, :text)
      add(:rp_id, :text)
      add(:allowed_actions, {:array, :text}, null: false, default: [])
      add(:delegation_signature, :text)
      add(:delegation_expires_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
    end

    create(unique_index(:webauthn_credentials, [:delegation_id]))
    create(index(:webauthn_credentials, [:did, :revoked_at]))

    alter table(:webauthn_challenges) do
      add(:session_id, :text)
      add(:operation_id, :text)
      add(:operation_hash, :text)
      add(:binding, :map)
    end

    create(index(:webauthn_challenges, [:operation_id]))

    create table(:web_publication_operations, primary_key: false) do
      add(:operation_id, :text, primary_key: true)
      add(:operation_hash, :text, null: false)
      add(:author_did, :text, null: false)
      add(:action, :text, null: false)
      add(:target_forum_host, :text, null: false)
      add(:board_id, :text, null: false)
      add(:entity_type, :text, null: false)
      add(:entity_id, :text, null: false)
      add(:operation, :map, null: false)
      add(:author_proof, :map, null: false)
      add(:host_receipt, :map, null: false)
      add(:status, :text, null: false, default: "accepted")
      add(:accepted_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:web_publication_operations, [:operation_hash]))
    create(index(:web_publication_operations, [:author_did, :accepted_at]))
    create(index(:web_publication_operations, [:board_id, :accepted_at]))
    create(index(:web_publication_operations, [:entity_type, :entity_id]))
  end
end
