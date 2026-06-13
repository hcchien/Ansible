import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/identity_anchor.dart';
import '../../entities/identity_anchor_chain.dart';
import '../identity_anchor_repository.dart';

class DriftIdentityAnchorRepository implements IdentityAnchorRepository {
  final AppDatabase _db;

  DriftIdentityAnchorRepository(this._db);

  @override
  Future<void> append(String did, IdentityAnchor anchor) async {
    await _db.transaction(() async {
      final cid = anchor.computeCid();

      final existing = await (_db.select(_db.identityAnchors)
            ..where((t) => t.cid.equals(cid)))
          .getSingleOrNull();
      if (existing != null) return; // idempotent

      final chain = await _orderedRows(did);
      final int chainIndex;
      if (chain.isEmpty) {
        if (anchor.reason != AnchorReason.initial ||
            anchor.prevAnchorCid != null) {
          throw StateError(
            'First anchor must be reason=initial with null prev_anchor_cid.',
          );
        }
        chainIndex = 0;
      } else {
        final expectedPrev = chain.last.cid;
        if (anchor.prevAnchorCid != expectedPrev) {
          throw StateError(
            'append would break the chain: prev_anchor_cid '
            '${anchor.prevAnchorCid} != latest CID $expectedPrev.',
          );
        }
        chainIndex = chain.last.chainIndex + 1;
      }

      await _db.into(_db.identityAnchors).insert(
            IdentityAnchorsCompanion.insert(
              cid: cid,
              did: did,
              handle: anchor.handle,
              identityKey: anchor.identityKey,
              custodyClass: anchor.custodyClass.storageValue,
              reason: anchor.reason.storageValue,
              prevAnchorCid: Value(anchor.prevAnchorCid),
              chainIndex: chainIndex,
              createdAt: anchor.createdAt,
              canonicalJson: anchor.canonicalJson(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
  }

  @override
  Future<List<IdentityAnchor>> list(String did) async {
    final rows = await _orderedRows(did);
    return rows
        .map((r) => IdentityAnchor.fromCanonicalJson(r.canonicalJson))
        .toList();
  }

  @override
  Future<IdentityAnchor?> latest(String did) async {
    final row = await (_db.select(_db.identityAnchors)
          ..where((t) => t.did.equals(did))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.chainIndex,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return IdentityAnchor.fromCanonicalJson(row.canonicalJson);
  }

  @override
  Future<AnchorChainVerification> verifyChain(String did) async {
    return IdentityAnchorChain.verify(await list(did));
  }

  @override
  Future<void> deleteAll(String did) async {
    await (_db.delete(_db.identityAnchors)..where((t) => t.did.equals(did)))
        .go();
  }

  Future<List<IdentityAnchorRow>> _orderedRows(String did) {
    return (_db.select(_db.identityAnchors)
          ..where((t) => t.did.equals(did))
          ..orderBy([(t) => OrderingTerm(expression: t.chainIndex)]))
        .get();
  }
}
