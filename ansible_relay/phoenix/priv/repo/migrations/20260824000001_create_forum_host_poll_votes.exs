defmodule AnsibleRelay.Repo.Migrations.CreateForumHostPollVotes do
  use Ecto.Migration

  def change do
    create table(:forum_host_poll_votes) do
      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:poll_id, :string, null: false)
      add(:option_id, :string, null: false)
      # A board-scoped SHA-256 digest prevents duplicate votes without retaining
      # a public or queryable voter identity.
      add(:voter_hash, :string, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:forum_host_poll_votes, [:hosted_board_id, :poll_id, :voter_hash]))
    create(index(:forum_host_poll_votes, [:hosted_board_id, :poll_id, :option_id]))
  end
end
