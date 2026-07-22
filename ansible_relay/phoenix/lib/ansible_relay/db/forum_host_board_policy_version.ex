defmodule AnsibleRelay.Db.ForumHostBoardPolicyVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_board_policy_versions" do
    field(:policy_hash, :string)
    field(:hosted_board_id, :string)
    field(:version, :integer)
    field(:canonical_policy, :map)
    field(:actor_did, :string)
    field(:approvals, :map, default: %{})
    field(:effective_at, :utc_datetime_usec)
    field(:superseded_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :policy_hash,
      :hosted_board_id,
      :version,
      :canonical_policy,
      :actor_did,
      :approvals,
      :effective_at,
      :superseded_at
    ])
    |> validate_required([
      :policy_hash,
      :hosted_board_id,
      :version,
      :canonical_policy,
      :actor_did,
      :effective_at
    ])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:hosted_board_id, :version])
  end
end
