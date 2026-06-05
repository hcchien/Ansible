import '../../entities/did_reputation.dart';
import '../did_reputation_repository.dart';

class InMemoryDidReputationRepository implements DidReputationRepository {
  final Map<String, DidReputation> _byDid = {};

  @override
  Future<void> put(String did, String tier, {DateTime? updatedAt}) async {
    if (did.isEmpty) return;
    _byDid[did] = DidReputation(
      did: did,
      tier: tier,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  Future<String> tierFor(String did) async => _byDid[did]?.tier ?? 'basic';

  @override
  Future<Map<String, String>> tiersFor(Iterable<String> dids) async {
    final out = <String, String>{};
    for (final did in dids) {
      final entry = _byDid[did];
      if (entry != null) out[did] = entry.tier;
    }
    return out;
  }

  @override
  Future<List<DidReputation>> list() async => _byDid.values.toList();
}
