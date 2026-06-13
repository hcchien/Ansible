defmodule AnsibleRelay.Db.DevicePushToken do
  @moduledoc """
  An opaque per-device push token bound to a DID (Phase B notifications).

  Holds only what wake scheduling needs: the transport token, the platform,
  and the wake categories the user opted into. Never content, never read
  state — unregistering deletes the row outright.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  schema "device_push_tokens" do
    field(:subject_did, :string)
    field(:device_id, :string)
    field(:push_token, :string)
    field(:platform, :string)
    field(:categories, {:array, :string}, default: [])

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:subject_did, :device_id, :push_token, :platform, :categories])
    |> validate_required([:subject_did, :device_id, :push_token, :platform])
    |> unique_constraint([:subject_did, :device_id],
      name: :device_push_tokens_subject_device_index
    )
  end
end
