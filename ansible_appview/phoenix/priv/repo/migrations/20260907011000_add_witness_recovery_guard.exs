defmodule AnsibleAppview.Repo.Migrations.AddWitnessRecoveryGuard do
  use Ecto.Migration

  def change do
    alter table(:authority_frontiers) do
      add(:pending, :map)
      add(:pending_since, :utc_datetime_usec)
    end
  end
end
