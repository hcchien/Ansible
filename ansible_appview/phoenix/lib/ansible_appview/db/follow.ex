defmodule AnsibleAppview.Db.Follow do
  use Ecto.Schema

  @primary_key false
  schema "appview_follows" do
    field :follower_did, :string, primary_key: true
    field :author_did, :string, primary_key: true
    field :created_log_id, :integer
  end
end
