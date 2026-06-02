defmodule AnsibleRelay.Db.ForumHostAcceptedIntent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:intent_id, :string, autogenerate: false}
  schema "forum_host_accepted_intents" do
    field(:author_did, :string)
    field(:action, :string)
    field(:payload_hash, :string)
    field(:result_kind, :string)
    field(:result_id, :string)
    field(:accepted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(intent, attrs) do
    intent
    |> cast(attrs, [
      :intent_id,
      :author_did,
      :action,
      :payload_hash,
      :result_kind,
      :result_id,
      :accepted_at
    ])
    |> validate_required([
      :intent_id,
      :author_did,
      :action,
      :payload_hash,
      :result_kind,
      :result_id,
      :accepted_at
    ])
  end
end
