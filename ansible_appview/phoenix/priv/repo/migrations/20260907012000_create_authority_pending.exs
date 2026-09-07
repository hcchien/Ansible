defmodule AnsibleAppview.Repo.Migrations.CreateAuthorityPending do
  use Ecto.Migration

  def change do
    create table(:authority_pending, primary_key: false) do
      add(:did, :text, primary_key: true)
      add(:op_id, :text, primary_key: true)
      add(:digest, :text, null: false)
      add(:log_id, :bigint, null: false)
      add(:reason, :text, null: false)
    end
  end
end
