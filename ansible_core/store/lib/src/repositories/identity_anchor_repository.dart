import '../entities/identity_anchor.dart';
import '../entities/identity_anchor_chain.dart';

/// Local store of a DID's hash-chained identity anchor chain (design Task 2:
/// "anchor chain persistence").
abstract class IdentityAnchorRepository {
  /// Appends [anchor] to [did]'s chain.
  ///
  /// Enforces chain soundness on write: the genesis anchor must be `initial`
  /// with a null `prev_anchor_cid`; every later anchor's `prev_anchor_cid` must
  /// equal the CID of the current latest anchor. Throws [StateError] when the
  /// append would break the chain. Idempotent: appending an anchor whose CID
  /// already exists is a no-op.
  Future<void> append(String did, IdentityAnchor anchor);

  /// The full chain for [did], genesis first, newest last.
  Future<List<IdentityAnchor>> list(String did);

  /// The newest anchor for [did], or null if none.
  Future<IdentityAnchor?> latest(String did);

  /// Verifies the persisted chain for [did] (structure, link integrity,
  /// signature presence, reason validity). Reads the chain and runs
  /// [IdentityAnchorChain.verify].
  Future<AnchorChainVerification> verifyChain(String did);

  /// Deletes every anchor for [did] (local only; e.g. identity reset).
  Future<void> deleteAll(String did);
}
