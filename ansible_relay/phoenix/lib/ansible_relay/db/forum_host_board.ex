defmodule AnsibleRelay.Db.ForumHostBoard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:hosted_board_id, :string, autogenerate: false}
  @derive {Jason.Encoder,
           only: [
             :hosted_board_id,
             :slug,
             :canonical_board_uri,
             :title,
             :description,
             :language,
             :tags,
             :permissions,
             :posting_policy,
             :moderation_policy
           ]}
  schema "forum_host_boards" do
    field(:slug, :string)
    field(:canonical_board_uri, :string)
    field(:title, :string)
    field(:description, :string)
    field(:language, :string)
    field(:tags, {:array, :string}, default: [])
    field(:permissions, :map, default: %{})
    field(:posting_policy, :map, default: %{})
    field(:moderation_policy, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [
      :hosted_board_id,
      :slug,
      :canonical_board_uri,
      :title,
      :description,
      :language,
      :tags,
      :permissions,
      :posting_policy,
      :moderation_policy
    ])
    |> validate_required([:hosted_board_id, :slug, :canonical_board_uri, :title])
    |> unique_constraint(:hosted_board_id, name: :forum_host_boards_pkey)
    |> unique_constraint(:slug)
    |> unique_constraint(:canonical_board_uri)
  end
end
