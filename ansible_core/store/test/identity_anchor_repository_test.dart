import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

const _did = 'did:plc:alice';

IdentityAnchor _genesis() => IdentityAnchor(
      did: _did,
      handle: 'alice.elix.cool',
      identityKey: 'aa' * 32,
      custodyClass: CustodyClass.software,
      reason: AnchorReason.initial,
      createdAt: DateTime.utc(2026, 6, 1),
      sig: 'g',
    );

IdentityAnchor _next(IdentityAnchor prev,
        {AnchorReason reason = AnchorReason.rotation}) =>
    IdentityAnchor(
      did: prev.did,
      handle: prev.handle,
      identityKey: 'bb' * 32,
      custodyClass: CustodyClass.software,
      reason: reason,
      createdAt: prev.createdAt.add(const Duration(days: 1)),
      prevAnchorCid: prev.computeCid(),
      sig: 'n',
    );

void main() {
  group('IdentityAnchorRepository', () {
    for (final (label, makeRepo)
        in <(String, IdentityAnchorRepository Function(AppDatabase db))>[
      ('drift', DriftIdentityAnchorRepository.new),
      ('in-memory', (_) => InMemoryIdentityAnchorRepository()),
    ]) {
      group(label, () {
        late AppDatabase db;
        late IdentityAnchorRepository repo;

        setUp(() {
          db = AppDatabase(NativeDatabase.memory());
          repo = makeRepo(db);
        });

        tearDown(() => db.close());

        test('append, list, latest', () async {
          final g = _genesis();
          final r1 = _next(g);
          await repo.append(_did, g);
          await repo.append(_did, r1);

          final chain = await repo.list(_did);
          expect(chain, hasLength(2));
          expect(chain.first.reason, AnchorReason.initial);
          expect(chain.last.reason, AnchorReason.rotation);

          final latest = await repo.latest(_did);
          expect(latest!.computeCid(), r1.computeCid());
        });

        test('latest is null for an unknown DID', () async {
          expect(await repo.latest('did:plc:nobody'), isNull);
          expect(await repo.list('did:plc:nobody'), isEmpty);
        });

        test('append is idempotent on duplicate CID', () async {
          final g = _genesis();
          await repo.append(_did, g);
          await repo.append(_did, g);
          expect(await repo.list(_did), hasLength(1));
        });

        test('rejects a non-initial genesis', () async {
          expect(
            () => repo.append(_did, _next(_genesis())),
            throwsA(isA<StateError>()),
          );
        });

        test('rejects an append that breaks the chain', () async {
          final g = _genesis();
          await repo.append(_did, g);
          // Build a "next" whose prev points at a stale/wrong CID.
          final wrong = IdentityAnchor(
            did: _did,
            handle: 'alice.elix.cool',
            identityKey: 'cc' * 32,
            custodyClass: CustodyClass.software,
            reason: AnchorReason.rotation,
            createdAt: DateTime.utc(2026, 6, 3),
            prevAnchorCid: 'sha256:wrong',
            sig: 'x',
          );
          expect(
            () => repo.append(_did, wrong),
            throwsA(isA<StateError>()),
          );
        });

        test('verifyChain on read accepts a valid persisted chain', () async {
          final g = _genesis();
          final r1 = _next(g);
          final r2 = _next(r1, reason: AnchorReason.recovery);
          await repo.append(_did, g);
          await repo.append(_did, r1);
          await repo.append(_did, r2);

          final result = await repo.verifyChain(_did);
          expect(result.isValid, isTrue, reason: result.toString());
        });

        test('chains for different DIDs are isolated', () async {
          await repo.append(_did, _genesis());
          await repo.append(
            'did:plc:bob',
            IdentityAnchor(
              did: 'did:plc:bob',
              handle: 'bob.elix.cool',
              identityKey: 'dd' * 32,
              custodyClass: CustodyClass.software,
              reason: AnchorReason.initial,
              createdAt: DateTime.utc(2026, 6, 1),
              sig: 'b',
            ),
          );
          expect(await repo.list(_did), hasLength(1));
          expect(await repo.list('did:plc:bob'), hasLength(1));
        });

        test('deleteAll clears the chain', () async {
          await repo.append(_did, _genesis());
          await repo.deleteAll(_did);
          expect(await repo.list(_did), isEmpty);
          expect(await repo.latest(_did), isNull);
        });
      });
    }
  });
}
