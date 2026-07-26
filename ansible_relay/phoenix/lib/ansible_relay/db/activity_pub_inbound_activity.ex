defmodule AnsibleRelay.Db.ActivityPubInboundActivity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activity_pub_inbound_activities" do
    field(:activity_id, :string)
    field(:local_actor, :string)
    field(:remote_actor, :string)
    field(:activity_type, :string)
    field(:object_id, :string)
    field(:payload, :map)
    field(:received_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :activity_id,
      :local_actor,
      :remote_actor,
      :activity_type,
      :object_id,
      :payload,
      :received_at
    ])
    |> validate_required([
      :activity_id,
      :local_actor,
      :remote_actor,
      :activity_type,
      :payload,
      :received_at
    ])
    |> unique_constraint(:activity_id)
  end
end
