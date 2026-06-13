import '../../entities/identity_anchor.dart';
import '../../entities/identity_anchor_chain.dart';
import '../identity_anchor_repository.dart';

class InMemoryIdentityAnchorRepository implements IdentityAnchorRepository {
  /// did -> chain (genesis first).
  final Map<String, List<IdentityAnchor>> _chains = {};

  @override
  Future<void> append(String did, IdentityAnchor anchor) async {
    final chain = _chains.putIfAbsent(did, () => []);
    final cid = anchor.computeCid();

    // Idempotent re-append.
    if (chain.any((a) => a.computeCid() == cid)) return;

    if (chain.isEmpty) {
      if (anchor.reason != AnchorReason.initial ||
          anchor.prevAnchorCid != null) {
        throw StateError(
          'First anchor must be reason=initial with null prev_anchor_cid.',
        );
      }
    } else {
      final expectedPrev = chain.last.computeCid();
      if (anchor.prevAnchorCid != expectedPrev) {
        throw StateError(
          'append would break the chain: prev_anchor_cid '
          '${anchor.prevAnchorCid} != latest CID $expectedPrev.',
        );
      }
    }
    chain.add(anchor);
  }

  @override
  Future<List<IdentityAnchor>> list(String did) async {
    return List.unmodifiable(_chains[did] ?? const []);
  }

  @override
  Future<IdentityAnchor?> latest(String did) async {
    final chain = _chains[did];
    if (chain == null || chain.isEmpty) return null;
    return chain.last;
  }

  @override
  Future<AnchorChainVerification> verifyChain(String did) async {
    return IdentityAnchorChain.verify(await list(did));
  }

  @override
  Future<void> deleteAll(String did) async {
    _chains.remove(did);
  }
}
