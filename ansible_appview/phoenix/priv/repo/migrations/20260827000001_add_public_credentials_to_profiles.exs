defmodule AnsibleAppview.Repo.Migrations.AddPublicCredentialsToProfiles do
  use Ecto.Migration

  def change do
    alter table(:appview_profiles) do
      add(:public_credentials, :map, null: false, default: %{"items" => []})
    end
  end
end
