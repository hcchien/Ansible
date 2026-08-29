defmodule AnsibleRelay.Repo.Migrations.CreateForumHostContextNoteRatings do
  use Ecto.Migration

  def change do
    create table(:forum_host_context_note_ratings) do
      add(:note_id, :string, null: false)
      add(:target_ref, :string, null: false)
      add(:board_id, :string)
      add(:rater_did, :string, null: false)
      add(:rater_key, :string, null: false)
      add(:rater_tier, :string, null: false, default: "basic")
      add(:level, :string, null: false)
      add(:tags, {:array, :string}, null: false, default: [])
      add(:intent_id, :string, null: false)
      add(:signed_intent, :map, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:forum_host_context_note_ratings, [:note_id, :rater_key]))
    create(unique_index(:forum_host_context_note_ratings, [:intent_id]))
    create(index(:forum_host_context_note_ratings, [:target_ref]))
    create(index(:forum_host_context_note_ratings, [:board_id]))
  end
end
