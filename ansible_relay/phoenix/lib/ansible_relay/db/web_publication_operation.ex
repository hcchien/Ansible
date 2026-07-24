defmodule AnsibleRelay.Db.WebPublicationOperation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:operation_id, :string, autogenerate: false}
  schema "web_publication_operations" do
    field(:operation_hash, :string)
    field(:author_did, :string)
    field(:action, :string)
    field(:target_forum_host, :string)
    field(:board_id, :string)
    field(:entity_type, :string)
    field(:entity_id, :string)
    field(:operation, :map)
    field(:author_proof, :map)
    field(:host_receipt, :map)
    field(:status, :string, default: "accepted")
    field(:accepted_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :operation_id,
      :operation_hash,
      :author_did,
      :action,
      :target_forum_host,
      :board_id,
      :entity_type,
      :entity_id,
      :operation,
      :author_proof,
      :host_receipt,
      :status,
      :accepted_at
    ])
    |> validate_required([
      :operation_id,
      :operation_hash,
      :author_did,
      :action,
      :target_forum_host,
      :board_id,
      :entity_type,
      :entity_id,
      :operation,
      :author_proof,
      :host_receipt,
      :status,
      :accepted_at
    ])
    |> unique_constraint(:operation_id, name: :web_publication_operations_pkey)
    |> unique_constraint(:operation_hash)
  end
end
