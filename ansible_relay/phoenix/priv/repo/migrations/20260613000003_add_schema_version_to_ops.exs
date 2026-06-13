defmodule AnsibleRelay.Repo.Migrations.AddSchemaVersionToOps do
  use Ecto.Migration

  # Phase 0 — API versioning: ops carry the payload format version they were
  # authored with so the op format can evolve additively. Existing rows are
  # all version 1 by construction.
  def change do
    alter table(:ops) do
      add(:schema_version, :integer, null: false, default: 1)
    end
  end
end
