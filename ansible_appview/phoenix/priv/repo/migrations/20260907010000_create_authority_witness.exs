defmodule AnsibleAppview.Repo.Migrations.CreateAuthorityWitness do
  use Ecto.Migration

  def change do
    create table(:authority_frontiers, primary_key: false) do
      add(:did, :text, primary_key: true)
      add(:chain, :map, null: false)
      add(:sequence, :bigint, null: false)
      add(:observed_at, :utc_datetime_usec, null: false)
    end

    create table(:authority_revocations, primary_key: false) do
      add(:did, :text, primary_key: true)
      add(:credential_hash, :text, primary_key: true)
      add(:evidence, :map, null: false)
      add(:observed_at, :utc_datetime_usec, null: false)
    end

    create table(:authority_observations, primary_key: false) do
      add(:did, :text, primary_key: true)
      add(:op_id, :text, primary_key: true)
      add(:digest, :text, null: false)
      add(:authority, :map, null: false)
      add(:observed_at, :utc_datetime_usec, null: false)
    end
  end
end
