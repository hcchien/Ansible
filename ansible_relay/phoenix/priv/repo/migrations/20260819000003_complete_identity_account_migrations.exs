defmodule AnsibleRelay.Repo.Migrations.CompleteIdentityAccountMigrations do
  use Ecto.Migration

  def change do
    alter table(:did_elix_migrations) do
      add(:handle, :text)
      add(:state, :text, null: false, default: "completed")
      add(:completed_at, :utc_datetime_usec)
    end

    create(
      constraint(:did_elix_migrations, :did_elix_migrations_state,
        check: "state IN ('completed')"
      )
    )
  end
end
