defmodule AnsibleRelay.ReputationTierTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.ReputationTier

  test "orders basic < dns_verified < verified_human with unknown tiers below basic" do
    assert ReputationTier.rank("basic") < ReputationTier.rank("dns_verified")
    assert ReputationTier.rank("dns_verified") < ReputationTier.rank("verified_human")
    assert ReputationTier.rank("made_up_tier") < ReputationTier.rank("basic")
    assert ReputationTier.rank(nil) == 0
  end

  test "meets?/2 satisfies a gate at or above the required tier" do
    assert ReputationTier.meets?("basic", "basic")
    assert ReputationTier.meets?("verified_human", "basic")
    assert ReputationTier.meets?("verified_human", "verified_human")
    refute ReputationTier.meets?("basic", "verified_human")
    refute ReputationTier.meets?("dns_verified", "verified_human")
    refute ReputationTier.meets?("unknown", "basic")
  end

  test "only basic and verified_human are valid min_post_tier gates" do
    assert ReputationTier.valid_min_post_tier?("basic")
    assert ReputationTier.valid_min_post_tier?("verified_human")
    refute ReputationTier.valid_min_post_tier?("dns_verified")
    refute ReputationTier.valid_min_post_tier?("vip")
    refute ReputationTier.valid_min_post_tier?(nil)
  end
end
