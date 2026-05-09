defmodule AnsibleRelay.Db.PublicationIntent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "publication_intents" do
    field(:publication_id, :string)
    field(:intent_id, :string)
    field(:author_did, :string)
    field(:content_item_id, :string)
    field(:action, :string)
    field(:visibility, :string)
    field(:payload, :map)
    field(:payload_hash, :string)
    field(:signature, :string)
    field(:signature_scheme, :string)
    field(:status, :string)
    field(:delivery_status, :string)
    field(:received_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :publication_id,
      :intent_id,
      :author_did,
      :content_item_id,
      :action,
      :visibility,
      :payload,
      :payload_hash,
      :signature,
      :signature_scheme,
      :status,
      :delivery_status,
      :received_at
    ])
    |> validate_required([
      :publication_id,
      :intent_id,
      :author_did,
      :content_item_id,
      :action,
      :visibility,
      :payload_hash,
      :signature,
      :signature_scheme,
      :status,
      :delivery_status,
      :received_at
    ])
    |> unique_constraint(:publication_id, name: :publication_intents_publication_id_index)
    |> unique_constraint(:intent_id, name: :publication_intents_intent_id_index)
  end
end
