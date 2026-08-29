defmodule AnsibleAppview.Db.ContextNote do
  use Ecto.Schema

  @primary_key {:note_id, :string, autogenerate: false}
  schema "appview_context_notes" do
    field(:author_did, :string)
    field(:canonical_author_did, :string)
    field(:target_entity_type, :string)
    field(:target_entity_id, :string)
    field(:target_op_id, :string)
    field(:target_content_hash, :string)
    field(:body, :string)
    field(:sources, {:array, :map}, default: [])
    field(:board_id, :string)
    field(:created_at, :utc_datetime_usec)
    field(:updated_log_id, :integer)
    field(:source, :string)
    field(:signature, :string)
    field(:public_key_hex, :string)
    field(:verified_at, :utc_datetime_usec)
    field(:anchor_expires_at, :utc_datetime_usec)
    field(:deleted, :boolean, default: false)
    timestamps(type: :utc_datetime_usec)
  end
end
