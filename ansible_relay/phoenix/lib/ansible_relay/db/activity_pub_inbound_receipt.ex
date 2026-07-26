defmodule AnsibleRelay.Db.ActivityPubInboundReceipt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activity_pub_inbound_receipts" do
    field(:signature_hash, :string)
    field(:actor_uri, :string)
    field(:key_id, :string)
    field(:expires_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:signature_hash, :actor_uri, :key_id, :expires_at])
    |> validate_required([:signature_hash, :actor_uri, :key_id, :expires_at])
    |> unique_constraint(:signature_hash)
  end
end
