defmodule AnsibleAppview.Repo.Migrations.AddCanonicalAuthorDid do
  use Ecto.Migration

  def change do
    alter table(:feed_items) do
      add(:canonical_author_did, :string)
    end

    create(index(:feed_items, [:canonical_author_did, "log_id DESC"]))
  end
end
