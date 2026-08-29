defmodule AnsibleAppview.Db.FollowRequest do
  use Ecto.Schema

  @primary_key {:request_op_id, :string, autogenerate: false}
  schema "appview_follow_requests" do
    field(:follower_did, :string)
    field(:author_did, :string)
    field(:created_log_id, :integer)
  end
end
