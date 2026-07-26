/// Client-side view of board posting gates (`posting_policy.min_post_tier`).
///
/// This is UX sugar only — the relay re-checks the tier at intent acceptance
/// and remains authoritative. Keeping the ordering here lets the app disable
/// the composer and explain the requirement *before* the user writes anything
/// (constitution Base Rule 6: the gate must be discoverable before posting).
library;

abstract final class PostingGate {
  static const String basicTier = 'basic';
  static const String humanityLimitedTier = 'humanity_limited';
  static const String verifiedHumanTier = 'verified_human';
  static const String uniqueHumanTier = 'unique_human';

  /// Reason code the relay returns when a write is rejected by the gate.
  static const String requiresTierErrorCode = 'posting_requires_tier';

  /// Tier ordering. Unknown tiers rank below `basic` so a future tier the
  /// client does not understand fails closed (relay still decides for real).
  static const Map<String, int> _rank = {
    basicTier: 0,
    humanityLimitedTier: 1,
    verifiedHumanTier: 2,
    uniqueHumanTier: 3,
  };

  static bool isHumanAssured(String? tier) =>
      tier == humanityLimitedTier ||
      tier == verifiedHumanTier ||
      tier == uniqueHumanTier;

  static bool isVerifiedHuman(String? tier) =>
      satisfies(tier ?? basicTier, verifiedHumanTier);

  /// Minimum tier required by [postingPolicy], or null when ungated.
  static String? minPostTier(Map<String, Object?> postingPolicy) {
    final tier = postingPolicy['min_post_tier'];
    if (tier is String && tier.trim().isNotEmpty) return tier;
    return null;
  }

  /// Whether [currentTier] satisfies [requiredTier]. A null [requiredTier]
  /// means the board is ungated.
  static bool satisfies(String currentTier, String? requiredTier) {
    if (requiredTier == null) return true;
    final required = _rank[requiredTier];
    if (required == null) {
      // Unknown requirement: be conservative and block client-side.
      return false;
    }
    final current = _rank[currentTier] ?? -1;
    return current >= required;
  }
}
