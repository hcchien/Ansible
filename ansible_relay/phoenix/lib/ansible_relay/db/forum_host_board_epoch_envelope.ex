defmodule AnsibleRelay.Db.ForumHostBoardEpochEnvelope do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_board_epoch_envelopes" do
    field(:epoch_id, :binary_id)
    field(:recipient_device_key_id, :binary_id)
    field(:sender_public_key_hash, :string)
    field(:envelope, :map)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(envelope, attrs) do
    envelope
    |> cast(attrs, [
      :epoch_id,
      :recipient_device_key_id,
      :sender_public_key_hash,
      :envelope
    ])
    |> validate_required([
      :epoch_id,
      :recipient_device_key_id,
      :sender_public_key_hash,
      :envelope
    ])
    |> unique_constraint([:epoch_id, :recipient_device_key_id])
  end
end
