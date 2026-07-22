defmodule AnsibleRelay.Db.ForumHostBoardDeviceKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_board_device_keys" do
    field(:hosted_board_id, :string)
    field(:device_key_id, :string)
    field(:agreement_public_key_hex, :string)
    field(:public_key_hash, :string)
    field(:pairwise_subject_hash, :string)
    field(:device_signing_thumbprint, :string)
    field(:policy_version, :integer)
    field(:state, :string, default: "active")
    field(:revoked_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, [
      :hosted_board_id,
      :device_key_id,
      :agreement_public_key_hex,
      :public_key_hash,
      :pairwise_subject_hash,
      :device_signing_thumbprint,
      :policy_version,
      :state,
      :revoked_at
    ])
    |> validate_required([
      :hosted_board_id,
      :device_key_id,
      :agreement_public_key_hex,
      :public_key_hash,
      :pairwise_subject_hash,
      :device_signing_thumbprint,
      :policy_version,
      :state
    ])
    |> validate_inclusion(:state, ["active", "revoked"])
    |> unique_constraint([:hosted_board_id, :device_key_id])
    |> unique_constraint([:hosted_board_id, :public_key_hash])
  end
end
