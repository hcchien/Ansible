defmodule AnsibleRelay.Repo.Migrations.CreatePublicProfileCredentials do
  use Ecto.Migration

  def change do
    create table(:public_profile_credentials, primary_key: false) do
      add(:did, :string, null: false, primary_key: true)
      add(:credential_type, :string, null: false, primary_key: true)
      add(:issuer_did, :string, null: false)
      add(:badge_key, :string, null: false)
      add(:badge_value, :string, null: false)
      add(:valid_until, :utc_datetime_usec, null: false)
      add(:verified_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:public_profile_credentials, [:did, :valid_until]))
  end
end
