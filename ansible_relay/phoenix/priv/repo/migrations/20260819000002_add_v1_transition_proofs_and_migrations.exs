defmodule AnsibleRelay.Repo.Migrations.AddV1TransitionProofsAndMigrations do
  use Ecto.Migration

  def change do
    alter table(:identity_anchors) do
      add(:authorization_sig, :text)
    end

    create table(:did_elix_migrations, primary_key: false) do
      add(:legacy_did, :text, primary_key: true)
      add(:v1_did, :text, null: false)
      add(:canonical_body, :text, null: false)
      add(:legacy_sig, :text, null: false)
      add(:v1_sig, :text, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:did_elix_migrations, [:v1_did]))
  end
end
