defmodule AnsibleRelay.Db.ForumHostBoardEncryptionEpoch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_board_encryption_epochs" do
    field(:hosted_board_id, :string)
    field(:epoch, :integer)
    field(:policy_version, :integer)
    field(:state, :string)
    field(:created_by_subject_hash, :string)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(epoch, attrs) do
    epoch
    |> cast(attrs, [
      :hosted_board_id,
      :epoch,
      :policy_version,
      :state,
      :created_by_subject_hash
    ])
    |> validate_required([
      :hosted_board_id,
      :epoch,
      :policy_version,
      :state,
      :created_by_subject_hash
    ])
    |> validate_number(:epoch, greater_than: 0)
    |> validate_inclusion(:state, ["ready", "superseded"])
    |> unique_constraint([:hosted_board_id, :epoch])
  end
end
