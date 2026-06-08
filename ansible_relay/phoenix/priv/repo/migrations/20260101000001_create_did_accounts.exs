defmodule AnsibleRelay.Repo.Migrations.CreateDidAccounts do
  use Ecto.Migration

  def change do
    create table(:did_accounts, primary_key: false) do
      add :did,            :string, primary_key: true, null: false
      add :public_key_hex, :string, null: false
      add :handle,         :string, null: false
      add :pds_endpoint,   :string, null: false, default: "https://elix.cool"
      add :reputation_tier,:string, null: false, default: "basic"  # basic | dns_verified | verified_human
      add :registered_at,  :utc_datetime_usec, null: false
      add :expires_at,     :utc_datetime_usec, null: false
    end

    create unique_index(:did_accounts, [:handle])
    create index(:did_accounts, [:expires_at])
    create index(:did_accounts, [:reputation_tier])
  end
end
