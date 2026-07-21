defmodule AnsibleRelay.Db.WebauthnCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:credential_id, :binary, autogenerate: false}
  schema "webauthn_credentials" do
    field(:did, :string)
    field(:cose_key, :binary)
    field(:transports, {:array, :string}, default: [])
    field(:sign_count, :integer, default: 0)
    field(:last_used_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:credential_id, :did, :cose_key, :transports, :sign_count, :last_used_at])
    |> validate_required([:credential_id, :did, :cose_key])
    |> unique_constraint(:credential_id, name: :webauthn_credentials_pkey)
  end
end
