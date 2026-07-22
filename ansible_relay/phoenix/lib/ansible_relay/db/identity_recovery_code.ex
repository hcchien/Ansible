defmodule AnsibleRelay.Db.IdentityRecoveryCode do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  schema "identity_recovery_codes" do
    field(:did, :string)
    field(:code_id, :string)
    field(:code_hash, :string)
    field(:hint, :string)
    field(:state, :string, default: "active")
    field(:used_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:did, :code_id, :code_hash, :hint, :state, :used_at, :revoked_at])
    |> validate_required([:did, :code_id, :code_hash, :hint, :state])
    |> validate_inclusion(:state, ~w(active used revoked))
    |> unique_constraint([:did, :code_id])
    |> unique_constraint([:did, :code_hash])
  end
end
