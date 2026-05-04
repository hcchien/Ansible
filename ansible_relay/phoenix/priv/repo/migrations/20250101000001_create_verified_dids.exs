defmodule AnsibleRelay.Repo.Migrations.CreateVerifiedDids do
  use Ecto.Migration

  def change do
    create table(:verified_dids, primary_key: false) do
      add :did,            :string, primary_key: true, null: false
      add :public_key_hex, :string, null: false
      add :nullifier,      :string, null: false
      add :verified_at,    :utc_datetime_usec, null: false
      add :expires_at,     :utc_datetime_usec, null: false
    end

    create unique_index(:verified_dids, [:nullifier], name: :verified_dids_nullifier_index)
    create index(:verified_dids, [:expires_at])
  end
end
