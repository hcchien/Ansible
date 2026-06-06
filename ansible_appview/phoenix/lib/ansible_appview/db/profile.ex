defmodule AnsibleAppview.Db.Profile do
  use Ecto.Schema

  @primary_key {:did, :string, autogenerate: false}
  schema "appview_profiles" do
    field :handle, :string
    field :display_name, :string
    field :bio, :string
    field :avatar_url, :string
    field :author_tier, :string, default: "basic"
    field :updated_log_id, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
