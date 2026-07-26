defmodule AnsibleRelay.Repo.Migrations.CreateFediversePreferences do
  use Ecto.Migration

  def change do
    create table(:fediverse_preferences) do
      add(:did, :string, null: false)
      add(:actor, :string, null: false)
      add(:enabled, :boolean, null: false, default: false)
      add(:default_note_visibility, :string, null: false, default: "public")
      add(:allow_remote_followers, :boolean, null: false, default: true)
      add(:domain_policy, :string, null: false, default: "open")
      add(:allowed_domains, {:array, :string}, null: false, default: [])
      add(:blocked_domains, {:array, :string}, null: false, default: [])
      add(:blocked_actors, {:array, :string}, null: false, default: [])
      add(:revision, :bigint, null: false)
      add(:signature, :text, null: false)
      add(:signature_scheme, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:fediverse_preferences, [:did]))
    create(unique_index(:fediverse_preferences, [:actor]))
  end
end

