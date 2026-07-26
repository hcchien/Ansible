defmodule AnsibleRelay.ReputationTierTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.ReputationTier

  test "orders human assurance levels and keeps unknown tiers below basic" do
    assert ReputationTier.rank("basic") < ReputationTier.rank("dns_verified")
    assert ReputationTier.rank("dns_verified") < ReputationTier.rank("humanity_limited")
    assert ReputationTier.rank("humanity_limited") < ReputationTier.rank("verified_human")
    assert ReputationTier.rank("verified_human") < ReputationTier.rank("unique_human")
    assert ReputationTier.rank("made_up_tier") < ReputationTier.rank("basic")
    assert ReputationTier.rank(nil) == 0
  end

  test "meets?/2 satisfies a gate at or above the required tier" do
    assert ReputationTier.meets?("basic", "basic")
    assert ReputationTier.meets?("verified_human", "basic")
    assert ReputationTier.meets?("verified_human", "verified_human")
    assert ReputationTier.meets?("unique_human", "verified_human")
    refute ReputationTier.meets?("humanity_limited", "verified_human")
    refute ReputationTier.meets?("basic", "verified_human")
    refute ReputationTier.meets?("dns_verified", "verified_human")
    refute ReputationTier.meets?("unknown", "basic")
  end

  test "human assurance levels are valid min_post_tier gates" do
    assert ReputationTier.valid_min_post_tier?("basic")
    assert ReputationTier.valid_min_post_tier?("humanity_limited")
    assert ReputationTier.valid_min_post_tier?("verified_human")
    assert ReputationTier.valid_min_post_tier?("unique_human")
    refute ReputationTier.valid_min_post_tier?("dns_verified")
    refute ReputationTier.valid_min_post_tier?("vip")
    refute ReputationTier.valid_min_post_tier?(nil)
  end

  test "derives assurance from signed humanity claims with legacy compatibility" do
    legacy = %{"credentialSubject" => %{"humanVerified" => true}}

    strong = %{
      "credentialSubject" => %{
        "humanVerified" => true,
        "humanAssurance" => "verified",
        "uniquenessAssurance" => "strong"
      }
    }

    limited =
      put_in(strong, ["credentialSubject", "uniquenessAssurance"], "limited")

    liveness =
      limited
      |> put_in(["credentialSubject", "humanAssurance"], "liveness")

    assert ReputationTier.for_credential("TrisAuraHumanityCredential", legacy) ==
             "verified_human"

    assert ReputationTier.for_credential("TrisAuraHumanityCredential", strong) ==
             "unique_human"

    assert ReputationTier.for_credential("TrisAuraHumanityCredential", limited) ==
             "humanity_limited"

    assert ReputationTier.for_credential("TrisAuraHumanityCredential", liveness) ==
             "humanity_limited"

    assert ReputationTier.for_credential("EmailCredential", strong) == "basic"
  end
end
