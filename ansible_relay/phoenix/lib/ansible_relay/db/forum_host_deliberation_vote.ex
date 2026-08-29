defmodule AnsibleRelay.Db.ForumHostDeliberationVote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_host_deliberation_votes" do
    field(:deliberation_id, :binary_id)
    field(:statement_id, :binary_id)
    field(:participant_key, :string)
    field(:stance, :string)
    field(:last_intent_id, :string)
    field(:access_policy_version, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [
      :deliberation_id,
      :statement_id,
      :participant_key,
      :stance,
      :last_intent_id,
      :access_policy_version
    ])
    |> validate_required([
      :deliberation_id,
      :statement_id,
      :participant_key,
      :stance,
      :last_intent_id,
      :access_policy_version
    ])
    |> validate_inclusion(:stance, ~w(agree disagree pass))
    |> unique_constraint([:deliberation_id, :statement_id, :participant_key],
      name: :forum_host_deliberation_votes_participant_statement_index
    )
    |> unique_constraint(:last_intent_id)
  end
end
