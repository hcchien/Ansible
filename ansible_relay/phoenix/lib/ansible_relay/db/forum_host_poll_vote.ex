defmodule AnsibleRelay.Db.ForumHostPollVote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_host_poll_votes" do
    field(:hosted_board_id, :string)
    field(:poll_id, :string)
    field(:option_id, :string)
    field(:voter_hash, :string)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:hosted_board_id, :poll_id, :option_id, :voter_hash])
    |> validate_required([:hosted_board_id, :poll_id, :option_id, :voter_hash])
    |> validate_length(:poll_id, min: 1, max: 128)
    |> validate_length(:option_id, min: 1, max: 128)
    |> unique_constraint(:voter_hash,
      name: :forum_host_poll_votes_hosted_board_id_poll_id_voter_hash_index
    )
  end
end
