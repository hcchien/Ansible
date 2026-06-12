defmodule AnsibleRelay.ReputationTier do
  @moduledoc """
  Single source of truth for reputation tier ordering.

  Tiers order `basic < dns_verified < verified_human`; unknown tiers rank
  below `basic` so they never satisfy a gate. Board `posting_policy`
  gates (`min_post_tier`) may only require `basic` or `verified_human`.
  """

  @ranks %{"basic" => 1, "dns_verified" => 2, "verified_human" => 3}
  @allowed_min_post_tiers ~w(basic verified_human)

  @doc "Tier values a board posting policy may require."
  def allowed_min_post_tiers, do: @allowed_min_post_tiers

  @doc "Returns true when the value is a valid `min_post_tier` gate."
  def valid_min_post_tier?(tier), do: tier in @allowed_min_post_tiers

  @doc "Higher rank = higher trust. Unknown tiers rank 0 (prevents downgrade attacks)."
  def rank(tier) when is_binary(tier), do: Map.get(@ranks, tier, 0)
  def rank(_tier), do: 0

  @doc "Returns true when `current_tier` satisfies `required_tier`."
  def meets?(current_tier, required_tier), do: rank(current_tier) >= rank(required_tier)
end
