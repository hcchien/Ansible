defmodule AnsibleAppview.Repo.Migrations.CreateAppviewFollows do
  use Ecto.Migration

  def change do
    create table(:appview_follows, primary_key: false) do
      add :follower_did, :string, null: false, primary_key: true
      add :author_did, :string, null: false, primary_key: true
      add :created_log_id, :bigint
    end

    # Fan-out lookup: "who follows this author".
    create index(:appview_follows, [:author_did])
  end
end
