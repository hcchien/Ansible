defmodule AnsibleRelay.Db.DidAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:did, :string, autogenerate: false}
  schema "did_accounts" do
    field(:public_key_hex, :string)
    field(:signing_algorithm, :string, default: "ed25519")
    field(:key_version, :integer, default: 1)
    field(:handle, :string)
    field(:pds_endpoint, :string, default: "https://elix.cool")
    field(:reputation_tier, :string, default: "basic")
    field(:registered_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :did,
      :public_key_hex,
      :signing_algorithm,
      :key_version,
      :handle,
      :pds_endpoint,
      :reputation_tier,
      :registered_at,
      :expires_at
    ])
    |> validate_required([
      :did,
      :public_key_hex,
      :signing_algorithm,
      :key_version,
      :handle,
      :registered_at,
      :expires_at
    ])
    |> unique_constraint(:handle)
  end
end
