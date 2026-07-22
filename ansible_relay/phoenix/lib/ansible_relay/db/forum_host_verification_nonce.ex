defmodule AnsibleRelay.Db.ForumHostVerificationNonce do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:nonce_hash, :string, autogenerate: false}
  schema "forum_host_verification_nonces" do
    field(:state_hash, :string)
    field(:hosted_board_id, :string)
    field(:audience, :string)
    field(:policy_version, :integer)
    field(:action, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:consumed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(nonce, attrs) do
    nonce
    |> cast(attrs, [
      :nonce_hash,
      :state_hash,
      :hosted_board_id,
      :audience,
      :policy_version,
      :action,
      :expires_at,
      :consumed_at
    ])
    |> validate_required([
      :nonce_hash,
      :state_hash,
      :hosted_board_id,
      :audience,
      :policy_version,
      :action,
      :expires_at
    ])
    |> validate_number(:policy_version, greater_than: 0)
    |> validate_inclusion(:action, ["discover", "read", "post", "moderate"])
  end
end
