defmodule AnsibleRelay.Db.VerifiedDid do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:did, :string, autogenerate: false}
  schema "verified_dids" do
    field(:public_key_hex, :string)
    field(:signing_algorithm, :string, default: "ed25519")
    field(:key_version, :integer, default: 1)
    field(:nullifier, :string)
    field(:verified_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :did,
      :public_key_hex,
      :signing_algorithm,
      :key_version,
      :nullifier,
      :verified_at,
      :expires_at
    ])
    |> validate_required([
      :did,
      :public_key_hex,
      :signing_algorithm,
      :key_version,
      :nullifier,
      :verified_at,
      :expires_at
    ])
    |> unique_constraint(:nullifier, name: :verified_dids_nullifier_index)
  end
end
