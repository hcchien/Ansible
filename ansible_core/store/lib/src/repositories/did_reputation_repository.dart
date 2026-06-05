import '../entities/did_reputation.dart';

abstract class DidReputationRepository {
  /// Upsert the tier for [did].
  Future<void> put(String did, String tier, {DateTime? updatedAt});

  /// Tier for [did], or "basic" when unknown.
  Future<String> tierFor(String did);

  /// Tiers for a set of DIDs, keyed by DID (only known DIDs included).
  Future<Map<String, String>> tiersFor(Iterable<String> dids);

  Future<List<DidReputation>> list();
}
