defmodule AnsibleAppview.Repo.Migrations.AddAuthorTier do
  use Ecto.Migration

  def change do
    alter table(:feed_items) do
      add :author_tier, :string, null: false, default: "basic"
    end
  end
end
