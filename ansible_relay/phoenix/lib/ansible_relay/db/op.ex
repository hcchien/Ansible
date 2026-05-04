defmodule AnsibleRelay.Db.Op do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "ops" do
    field :op_id,       :string
    field :author_did,  :string
    field :entity_type, :string
    field :entity_id,   :string
    field :op_type,     :string
    field :payload,     :string
    field :signature,   :string
    field :received_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:op_id, :author_did, :entity_type, :entity_id, :op_type, :payload, :signature, :received_at])
    |> validate_required([:op_id, :author_did, :entity_type, :entity_id, :op_type, :payload, :signature])
    |> unique_constraint(:op_id, name: :ops_op_id_index)
  end
end
