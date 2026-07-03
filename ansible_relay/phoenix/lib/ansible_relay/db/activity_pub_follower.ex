defmodule AnsibleRelay.Db.ActivityPubFollower do
  @moduledoc "A remote AP actor following a local actor mirror."

  use Ecto.Schema
  import Ecto.Changeset

  schema "activity_pub_followers" do
    field(:actor, :string)
    field(:remote_actor, :string)
    field(:remote_inbox, :string)
    field(:follow_activity_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:actor, :remote_actor, :remote_inbox, :follow_activity_id])
    |> validate_required([:actor, :remote_actor, :remote_inbox])
    |> unique_constraint([:actor, :remote_actor],
      name: :activity_pub_followers_actor_remote_index
    )
  end
end
