defmodule AnsibleRelay.Repo.Migrations.CreateForumHostTables do
  use Ecto.Migration

  def change do
    create table(:forum_host_boards, primary_key: false) do
      add(:hosted_board_id, :string, primary_key: true)
      add(:slug, :string, null: false)
      add(:canonical_board_uri, :string, null: false)
      add(:title, :string, null: false)
      add(:description, :text)
      add(:language, :string)
      add(:tags, {:array, :string}, null: false, default: [])
      add(:permissions, :map, null: false, default: %{})
      add(:posting_policy, :map, null: false, default: %{})
      add(:moderation_policy, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:forum_host_boards, [:slug]))
    create(unique_index(:forum_host_boards, [:canonical_board_uri]))

    create table(:forum_host_announcements, primary_key: false) do
      add(:announcement_id, :string, primary_key: true)

      add(:owner_kind, :string, null: false)

      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :nilify_all
        )
      )

      add(:title, :string, null: false)
      add(:body, :text, null: false)
      add(:severity, :string, null: false, default: "info")
      add(:locale, :string)
      add(:url, :string)
      add(:starts_at, :utc_datetime_usec)
      add(:expires_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forum_host_announcements, [:owner_kind]))
    create(index(:forum_host_announcements, [:hosted_board_id]))

    create table(:forum_host_accepted_intents, primary_key: false) do
      add(:intent_id, :string, primary_key: true)
      add(:author_did, :string, null: false)
      add(:action, :string, null: false)
      add(:payload_hash, :string, null: false)
      add(:result_kind, :string, null: false)
      add(:result_id, :string, null: false)
      add(:accepted_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forum_host_accepted_intents, [:author_did]))
    create(index(:forum_host_accepted_intents, [:result_kind, :result_id]))
  end
end
