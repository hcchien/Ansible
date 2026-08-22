defmodule AnsibleRelay.Repo.Migrations.AddV1GenesisCommitment do
  use Ecto.Migration

  def change do
    alter table(:identity_anchors) do
      add(:genesis_commitment, :map)
    end
  end
end
