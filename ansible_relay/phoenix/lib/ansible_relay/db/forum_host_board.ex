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
    |> validate_posting_policy()
    |> validate_external_inclusion()
    |> unique_constraint(:hosted_board_id, name: :forum_host_boards_pkey)
    |> unique_constraint(:slug)
    |> unique_constraint(:canonical_board_uri)
  end

  # posting_policy["min_post_tier"] is optional (absent = no gate) but must be
  # a known tier when present so an unknown gate value can never be stored.
  defp validate_posting_policy(changeset) do
    validate_change(changeset, :posting_policy, fn :posting_policy, policy ->
      tier = Map.get(policy, "min_post_tier") || Map.get(policy, :min_post_tier)

      if is_nil(tier) or AnsibleRelay.ReputationTier.valid_min_post_tier?(tier) do
        []
      else
        allowed = Enum.join(AnsibleRelay.ReputationTier.allowed_min_post_tiers(), ", ")
        [posting_policy: "min_post_tier must be one of: #{allowed}"]
      end
    end)
  end

  # Constitution invariant: a board may not be both trust-gated (a verified-
  # humans 真人版 `min_post_tier`) and externally inclusive — a verified-only
  # board cannot carry unverified external content. `external_inclusion` lives
  # in `posting_policy` alongside `min_post_tier` so the mutual-exclusion check
  # is local to one map and surfaces wherever `posting_policy` already does.
  defp validate_external_inclusion(changeset) do
    validate_change(changeset, :posting_policy, fn :posting_policy, policy ->
      if external_inclusion?(policy) and gated_min_post_tier?(policy) do
        [posting_policy: "external_inclusion_conflicts_with_trust_gate"]
      else
        []
      end
    end)
  end

  defp external_inclusion?(%{} = policy) do
    case Map.get(policy, "external_inclusion") || Map.get(policy, :external_inclusion) do
      true -> true
      _value -> false
    end
  end

  defp external_inclusion?(_policy), do: false

  # A "gated" tier is any tier above the open baseline `basic` (e.g.
  # `verified_human`). `basic` is not a real-human gate, so it does not
  # conflict with external inclusion.
  defp gated_min_post_tier?(%{} = policy) do
    case Map.get(policy, "min_post_tier") || Map.get(policy, :min_post_tier) do
      tier when is_binary(tier) ->
        AnsibleRelay.ReputationTier.valid_min_post_tier?(tier) and tier != "basic"

      _value ->
        false
    end
  end

  defp gated_min_post_tier?(_policy), do: false
end
