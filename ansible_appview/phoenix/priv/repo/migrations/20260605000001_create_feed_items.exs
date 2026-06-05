defmodule AnsibleAppview.Repo.Migrations.CreateFeedItems do
  use Ecto.Migration

  def change do
    create table(:feed_items, primary_key: false) do
      add :log_id, :bigint, primary_key: true
      add :op_id, :string, null: false
      add :author_did, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :string, null: false
      add :op_type, :string, null: false
      add :board_id, :string
      add :thread_id, :string
      add :visibility, :string
      add :item_created_at, :utc_datetime_usec
      add :payload, :map
      add :public_key_hex, :string
      add :deleted, :boolean, null: false, default: false
      add :sig_verified, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:feed_items, [:op_id], name: :feed_items_op_id_index)
    create index(:feed_items, [:author_did, "log_id DESC"])
    create index(:feed_items, [:board_id, "log_id DESC"])

    create table(:ingest_cursors, primary_key: false) do
      add :source, :string, primary_key: true
      add :cursor, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end
  end
end
