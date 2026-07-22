defmodule AnsibleRelay.Repo.Migrations.AddIdentityRecoveryCodes do
  use Ecto.Migration

  def change do
    create table(:identity_recovery_codes) do
      add(:did, :string, null: false)
      add(:code_id, :string, null: false)
      add(:code_hash, :string, null: false)
      add(:hint, :string, null: false)
      add(:state, :string, null: false, default: "active")
      add(:used_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:identity_recovery_codes, [:did, :code_id]))
    create(unique_index(:identity_recovery_codes, [:did, :code_hash]))
    create(index(:identity_recovery_codes, [:did, :state]))

    create table(:identity_recovery_audit_events) do
      add(:did, :string, null: false)
      add(:event_type, :string, null: false)
      add(:reason_code, :string, null: false)
      add(:anchor_cid, :string)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:identity_recovery_audit_events, [:did, :inserted_at]))
  end
end
