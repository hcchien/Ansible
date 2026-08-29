defmodule AnsibleRelay.Db.ForumHostBoardAccessGrant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:capability_hash, :string, autogenerate: false}
  schema "forum_host_board_access_grants" do
    field(:hosted_board_id, :string)
    field(:pairwise_subject_hash, :string)
    field(:device_key_thumbprint, :string)
    field(:audience, :string)
    field(:policy_version, :integer)
    field(:scopes, {:array, :string})
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    field(:revocation_reason, :string)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [
      :capability_hash,
      :hosted_board_id,
      :pairwise_subject_hash,
      :device_key_thumbprint,
      :audience,
      :policy_version,
      :scopes,
      :expires_at,
      :revoked_at,
      :revocation_reason
    ])
    |> validate_required([
      :capability_hash,
      :hosted_board_id,
      :pairwise_subject_hash,
      :device_key_thumbprint,
      :audience,
      :policy_version,
      :scopes,
      :expires_at
    ])
    |> validate_number(:policy_version, greater_than: 0)
    |> validate_subset(:scopes, ~w(discover read post moderate analyze key:read))
  end
end
