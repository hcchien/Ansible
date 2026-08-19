defmodule AnsibleRelay.Db.DidElixMigration do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:legacy_did, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  schema "did_elix_migrations" do
    field(:v1_did, :string)
    field(:canonical_body, :string)
    field(:legacy_sig, :string)
    field(:v1_sig, :string)
    field(:created_at, :utc_datetime_usec)
    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, ~w(legacy_did v1_did canonical_body legacy_sig v1_sig created_at)a)
    |> validate_required(~w(legacy_did v1_did canonical_body legacy_sig v1_sig created_at)a)
    |> unique_constraint(:legacy_did, name: :did_elix_migrations_pkey)
    |> unique_constraint(:v1_did)
  end
end
