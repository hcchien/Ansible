defmodule AnsibleRelay.Repo.Migrations.CreateOps do
  use Ecto.Migration

  def change do
    create table(:ops) do
      add :op_id,       :string, null: false
      add :author_did,  :string, null: false
      add :entity_type, :string, null: false
      add :entity_id,   :string, null: false
      add :op_type,     :string, null: false
      add :payload,     :text, null: false
      add :signature,   :string, null: false
      add :received_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ops, [:op_id], name: :ops_op_id_index)
    create index(:ops, [:author_did])
    create index(:ops, [:entity_id])
    create index(:ops, [:inserted_at])
  end
end
