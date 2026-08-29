defmodule AnsibleRelay.Db.ForumHostContextNoteRating do
  use Ecto.Schema
  import Ecto.Changeset

  @levels ~w(helpful somewhat_helpful not_helpful)

  schema "forum_host_context_note_ratings" do
    field(:note_id, :string)
    field(:target_ref, :string)
    field(:board_id, :string)
    field(:rater_did, :string)
    field(:rater_key, :string)
    field(:rater_tier, :string, default: "basic")
    field(:level, :string)
    field(:tags, {:array, :string}, default: [])
    field(:intent_id, :string)
    field(:signed_intent, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def levels, do: @levels

  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [
      :note_id,
      :target_ref,
      :board_id,
      :rater_did,
      :rater_key,
      :rater_tier,
      :level,
      :tags,
      :intent_id,
      :signed_intent
    ])
    |> validate_required([
      :note_id,
      :target_ref,
      :rater_did,
      :rater_key,
      :rater_tier,
      :level,
      :tags,
      :intent_id,
      :signed_intent
    ])
    |> validate_inclusion(:level, @levels)
    |> unique_constraint([:note_id, :rater_key])
    |> unique_constraint(:intent_id)
  end
end
