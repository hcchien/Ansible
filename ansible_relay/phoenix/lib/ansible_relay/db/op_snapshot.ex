defmodule AnsibleRelay.Db.OpSnapshot do
  @moduledoc """
  A relay-signed, content-addressed snapshot of op state up to a cursor.

  See `AnsibleRelay.SnapshotStore` for generation/verification and the Phase 2
  design notes (service architecture plan §Phase 2.3).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "op_snapshots" do
    field(:cursor, :integer)
    field(:snapshot_cid, :string)
    field(:digest, :string)
    field(:op_count, :integer)
    field(:signature, :string)
    field(:signing_public_key_hex, :string)
    field(:created_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :cursor,
      :snapshot_cid,
      :digest,
      :op_count,
      :signature,
      :signing_public_key_hex,
      :created_at
    ])
    |> validate_required([
      :cursor,
      :snapshot_cid,
      :digest,
      :op_count,
      :signature,
      :signing_public_key_hex,
      :created_at
    ])
    |> validate_number(:cursor, greater_than_or_equal_to: 0)
    |> validate_number(:op_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:snapshot_cid, name: :op_snapshots_cid_index)
  end
end
