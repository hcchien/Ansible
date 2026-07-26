defmodule AnsibleRelay.Db.ActivityPubAccountDeletion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activity_pub_account_deletions" do
    field(:did, :string)
    field(:actor, :string)
    field(:reason_code, :string, default: "user_requested")
    field(:follower_count, :integer, default: 0)
    field(:requested_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:did, :actor, :reason_code, :follower_count, :requested_at])
    |> validate_required([:did, :actor, :reason_code, :requested_at])
    |> unique_constraint(:did)
  end
end
