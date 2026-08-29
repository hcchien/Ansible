defmodule AnsibleAppview.Repo.Migrations.CreateAppviewFollowRequests do
  use Ecto.Migration

  def change do
    create table(:appview_follow_requests, primary_key: false) do
      add(:request_op_id, :text, primary_key: true)
      add(:follower_did, :text, null: false)
      add(:author_did, :text, null: false)
      add(:created_log_id, :bigint, null: false)
    end

    create(unique_index(:appview_follow_requests, [:follower_did, :author_did]))
  end
end
