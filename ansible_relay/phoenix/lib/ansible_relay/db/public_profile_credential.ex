defmodule AnsibleRelay.Db.PublicProfileCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "public_profile_credentials" do
    field(:did, :string, primary_key: true)
    field(:credential_type, :string, primary_key: true)
    field(:issuer_did, :string)
    field(:badge_key, :string)
    field(:badge_value, :string)
    field(:valid_until, :utc_datetime_usec)
    field(:verified_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(did credential_type issuer_did badge_key badge_value valid_until verified_at)a

  def changeset(row, attrs) do
    row
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end
