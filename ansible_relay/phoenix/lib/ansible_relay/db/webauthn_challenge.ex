defmodule AnsibleRelay.Db.WebauthnChallenge do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:challenge_id, :string, autogenerate: false}
  schema "webauthn_challenges" do
    field(:did, :string)
    field(:kind, :string)
    field(:scope, :string)
    field(:wax_challenge, :binary)
    field(:session_id, :string)
    field(:operation_id, :string)
    field(:operation_hash, :string)
    field(:binding, :map)
    field(:expires_at, :utc_datetime_usec)
    field(:consumed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :challenge_id,
      :did,
      :kind,
      :scope,
      :wax_challenge,
      :session_id,
      :operation_id,
      :operation_hash,
      :binding,
      :expires_at,
      :consumed_at
    ])
    |> validate_required([:challenge_id, :did, :kind, :scope, :wax_challenge, :expires_at])
  end
end
