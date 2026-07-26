defmodule AnsibleRelay.ReputationTier do
  @moduledoc """
  Single source of truth for reputation tier ordering.

  Human assurance orders `basic < humanity_limited < verified_human <
  unique_human`. `dns_verified` remains a legacy non-human reputation signal.
  Unknown tiers rank below `basic` so they never satisfy a gate.
  """

  @ranks %{
    "basic" => 1,
    "dns_verified" => 2,
    "humanity_limited" => 3,
    "verified_human" => 4,
    "unique_human" => 5
  }
  @allowed_min_post_tiers ~w(basic humanity_limited verified_human unique_human)

  @doc "Tier values a board posting policy may require."
  def allowed_min_post_tiers, do: @allowed_min_post_tiers

  @doc "Returns true when the value is a valid `min_post_tier` gate."
  def valid_min_post_tier?(tier), do: tier in @allowed_min_post_tiers

  @doc "Higher rank = higher trust. Unknown tiers rank 0 (prevents downgrade attacks)."
  def rank(tier) when is_binary(tier), do: Map.get(@ranks, tier, 0)
  def rank(_tier), do: 0

  @doc "Returns true when `current_tier` satisfies `required_tier`."
  def meets?(current_tier, required_tier), do: rank(current_tier) >= rank(required_tier)

  @doc "Derives a tier from an issuer-verified credential and its signed claims."
  def for_credential(credential_type, credential) do
    credential_type
    |> AnsibleRelay.HumanAssurance.from_credential(credential)
    |> AnsibleRelay.HumanAssurance.compatibility_tier()
  end
end
