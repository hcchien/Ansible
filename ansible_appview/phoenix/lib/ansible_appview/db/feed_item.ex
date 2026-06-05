defmodule AnsibleAppview.Db.FeedItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:log_id, :integer, autogenerate: false}
  schema "feed_items" do
    field :op_id, :string
    field :author_did, :string
    field :entity_type, :string
    field :entity_id, :string
    field :op_type, :string
    field :board_id, :string
    field :thread_id, :string
    field :visibility, :string
    field :item_created_at, :utc_datetime_usec
    field :payload, :map
    field :public_key_hex, :string
    field :deleted, :boolean, default: false
    field :sig_verified, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(log_id op_id author_did entity_type entity_id op_type board_id thread_id
             visibility item_created_at payload public_key_hex deleted sig_verified)a
  @required ~w(log_id op_id author_did entity_type entity_id op_type)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> unique_constraint(:op_id, name: :feed_items_op_id_index)
  end
end
