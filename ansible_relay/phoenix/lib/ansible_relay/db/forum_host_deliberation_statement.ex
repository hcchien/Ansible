defmodule AnsibleRelay.Db.ForumHostDeliberationStatement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_deliberation_statements" do
    field(:deliberation_id, :binary_id)
    field(:author_did, :string)
    field(:author_participant_key, :string)
    field(:text, :string)
    field(:state, :string, default: "accepted")
    field(:moderation_reason_code, :string)
    field(:last_intent_id, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(statement, attrs) do
    statement
    |> cast(attrs, [
      :deliberation_id,
      :author_did,
      :author_participant_key,
      :text,
      :state,
      :moderation_reason_code,
      :last_intent_id
    ])
    |> validate_required([
      :deliberation_id,
      :author_did,
      :author_participant_key,
      :text,
      :state,
      :last_intent_id
    ])
    |> update_change(:text, &String.trim/1)
    |> validate_length(:text, min: 1, max: 500)
    |> validate_inclusion(:state, ~w(pending accepted rejected withdrawn))
    |> unique_constraint(:last_intent_id)
  end
end
