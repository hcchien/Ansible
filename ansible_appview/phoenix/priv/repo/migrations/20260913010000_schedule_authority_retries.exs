defmodule AnsibleAppview.Repo.Migrations.ScheduleAuthorityRetries do
  use Ecto.Migration

  def change do
    alter table(:authority_pending) do
      add(:attempts, :integer, null: false, default: 0)
      add(:next_retry_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP"))
    end

    create(index(:authority_pending, [:next_retry_at, :log_id]))
  end
end
