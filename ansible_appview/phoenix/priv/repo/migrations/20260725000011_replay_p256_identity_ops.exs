defmodule AnsibleAppview.Repo.Migrations.ReplayP256IdentityOps do
  use Ecto.Migration

  @moduledoc """
  Replays the immutable Relay stream after AppView gains P-256 identity
  verification. Existing feed rows are idempotently upserted by log_id; P-256
  rows that the previous verifier rejected are added to the projection.
  """

  def up do
    execute("UPDATE ingest_cursors SET cursor = 0 WHERE source = 'relay'")
  end

  def down do
    :ok
  end
end
