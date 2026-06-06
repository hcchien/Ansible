defmodule AnsibleAppview.Repo.Migrations.CreateAppviewProfiles do
  use Ecto.Migration

  def change do
    create table(:appview_profiles, primary_key: false) do
      add :did, :string, null: false, primary_key: true
      add :handle, :string
      add :display_name, :string
      add :bio, :text
      add :avatar_url, :string
      add :author_tier, :string, default: "basic"
      add :updated_log_id, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    # Handle lookups and prefix search (case-insensitive).
    create index(:appview_profiles, ["lower(handle)"])
    create index(:appview_profiles, ["lower(display_name)"])
  end
end
