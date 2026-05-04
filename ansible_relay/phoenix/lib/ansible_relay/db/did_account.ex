defmodule AnsibleRelay.Db.DidAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:did, :string, autogenerate: false}
  schema "did_accounts" do
    field :public_key_hex, :string
    field :handle,         :string
    field :pds_endpoint,   :string, default: "https://trisaura.io"
    field :reputation_tier,:string, default: "basic"
    field :registered_at,  :utc_datetime_usec
    field :expires_at,     :utc_datetime_usec
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:did, :public_key_hex, :handle, :pds_endpoint, :reputation_tier, :registered_at, :expires_at])
    |> validate_required([:did, :public_key_hex, :handle, :registered_at, :expires_at])
    |> unique_constraint(:handle)
  end
end
