defmodule AnsibleRelay.Repo.Migrations.CreateWebauthnSyncCredentials do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials, primary_key: false) do
      add(:credential_id, :binary, primary_key: true)
      add(:did, :text, null: false)
      add(:cose_key, :binary, null: false)
      add(:transports, {:array, :text}, null: false, default: [])
      add(:sign_count, :bigint, null: false, default: 0)
      add(:last_used_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:webauthn_credentials, [:did]))

    create table(:webauthn_challenges, primary_key: false) do
      add(:challenge_id, :text, primary_key: true)
      add(:did, :text, null: false)
      add(:kind, :text, null: false)
      add(:scope, :text, null: false)
      add(:wax_challenge, :binary, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:consumed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:webauthn_challenges, [:did, :kind]))
    create(index(:webauthn_challenges, [:expires_at]))
  end
end
