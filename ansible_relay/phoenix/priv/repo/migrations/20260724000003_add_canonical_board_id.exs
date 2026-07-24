defmodule AnsibleRelay.Repo.Migrations.AddCanonicalBoardId do
  use Ecto.Migration

  def up do
    alter table(:forum_host_boards) do
      add(:board_id, :bigint)
    end

    execute("CREATE SEQUENCE forum_host_boards_board_id_seq")
    execute("UPDATE forum_host_boards SET board_id = nextval('forum_host_boards_board_id_seq')")
    execute("ALTER TABLE forum_host_boards ALTER COLUMN board_id SET DEFAULT nextval('forum_host_boards_board_id_seq')")
    execute("SELECT setval('forum_host_boards_board_id_seq', GREATEST((SELECT COALESCE(MAX(board_id), 1) FROM forum_host_boards), 1), true)")

    alter table(:forum_host_boards) do
      modify(:board_id, :bigint, null: false)
    end

    create(unique_index(:forum_host_boards, [:board_id]))
  end

  def down do
    drop(index(:forum_host_boards, [:board_id]))

    alter table(:forum_host_boards) do
      remove(:board_id)
    end

    execute("DROP SEQUENCE forum_host_boards_board_id_seq")
  end
end
