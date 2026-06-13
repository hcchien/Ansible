import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

const _key32a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _key32b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

IdentityAnchor _genesis({
  String did = 'did:plc:alice',
  String handle = 'alice.elix.cool',
  String identityKey = _key32a,
  String sig = 'beef',
}) {
  return IdentityAnchor(
    did: did,
    handle: handle,
    identityKey: identityKey,
    custodyClass: CustodyClass.software,
    reason: AnchorReason.initial,
    createdAt: DateTime.utc(2026, 6, 1, 12),
    sig: sig,
  );
}

IdentityAnchor _next(
  IdentityAnchor prev, {
  AnchorReason reason = AnchorReason.rotation,
  String identityKey = _key32b,
  String sig = 'cafe',
  String? prevCidOverride,
}) {
  return IdentityAnchor(
    did: prev.did,
    handle: prev.handle,
    identityKey: identityKey,
    custodyClass: CustodyClass.software,
    reason: reason,
    createdAt: prev.createdAt.add(const Duration(days: 1)),
    prevAnchorCid: prevCidOverride ?? prev.computeCid(),
    sig: sig,
  );
}

void main() {
  group('IdentityAnchor', () {
    test('canonical body is deterministic and CID is stable', () {
      final a = _genesis();
      final b = _genesis();
      expect(a.canonicalBodyJson(), b.canonicalBodyJson());
      expect(a.computeCid(), b.computeCid());
      expect(a.computeCid(), startsWith('sha256:'));
    });

    test('changing the body changes the CID', () {
      final a = _genesis();
      final b = _genesis(handle: 'bob.elix.cool');
      expect(a.computeCid(), isNot(b.computeCid()));
    });

    test('round-trips through canonical JSON', () {
      final original = _next(
        _genesis(),
        reason: AnchorReason.recovery,
      );
      final restored = IdentityAnchor.fromCanonicalJson(
        original.canonicalJson(),
      );
      expect(restored.did, original.did);
      expect(restored.reason, AnchorReason.recovery);
      expect(restored.prevAnchorCid, original.prevAnchorCid);
      expect(restored.computeCid(), original.computeCid());
    });

    test('serializes device records', () {
      final anchor = IdentityAnchor(
        did: 'did:plc:alice',
        handle: 'alice.elix.cool',
        identityKey: 'aa' * 32,
        custodyClass: CustodyClass.software,
        reason: AnchorReason.deviceChange,
        createdAt: DateTime.utc(2026, 6, 2),
        prevAnchorCid: 'sha256:abc',
        sig: 'sig',
        deviceSig: 'devsig',
        devices: [
          AnchorDeviceRecord(
            deviceId: 'device-1',
            deviceKey: 'cc' * 32,
            custodyClass: CustodyClass.software,
            enrolledAt: DateTime.utc(2026, 6, 2),
            attestationSig: 'attest',
          ),
        ],
      );
      final restored = IdentityAnchor.fromCanonicalJson(anchor.canonicalJson());
      expect(restored.devices, hasLength(1));
      expect(restored.devices.single.deviceId, 'device-1');
      expect(restored.deviceSig, 'devsig');
    });
  });

  group('IdentityAnchorChain.verify', () {
    test('accepts a valid chain', () {
      final g = _genesis();
      final r1 = _next(g);
      final r2 = _next(r1, reason: AnchorReason.recovery, sig: 'feed');
      final result = IdentityAnchorChain.verify([g, r1, r2]);
      expect(result.isValid, isTrue, reason: result.toString());
    });

    test('rejects an empty chain', () {
      final result = IdentityAnchorChain.verify([]);
      expect(result.isValid, isFalse);
      expect(result.error, AnchorChainError.empty);
    });

    test('rejects a genesis that is not reason=initial', () {
      final bad = IdentityAnchor(
        did: 'did:plc:alice',
        handle: 'alice.elix.cool',
        identityKey: 'aa' * 32,
        custodyClass: CustodyClass.software,
        reason: AnchorReason.rotation,
        createdAt: DateTime.utc(2026, 6, 1),
        sig: 'beef',
      );
      final result = IdentityAnchorChain.verify([bad]);
      expect(result.isValid, isFalse);
      expect(result.error, AnchorChainError.genesisNotInitial);
    });

    test('rejects a broken link', () {
      final g = _genesis();
      final broken = _next(g, prevCidOverride: 'sha256:not-the-real-prev');
      final result = IdentityAnchorChain.verify([g, broken]);
      expect(result.isValid, isFalse);
      expect(result.error, AnchorChainError.brokenLink);
      expect(result.failedAtIndex, 1);
    });

    test('rejects a missing signature', () {
      final g = _genesis();
      final noSig = _next(g, sig: '   ');
      final result = IdentityAnchorChain.verify([g, noSig]);
      expect(result.isValid, isFalse);
      expect(result.error, AnchorChainError.missingSignature);
      expect(result.failedAtIndex, 1);
    });

    test('rejects an unknown reason at construction time', () {
      expect(
        () => AnchorReason.parse('hijack'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an unsupported schema version', () {
      final g = _genesis();
      final future = IdentityAnchor(
        schemaVersion: IdentityAnchor.currentSchemaVersion + 1,
        did: g.did,
        handle: g.handle,
        identityKey: 'bb' * 32,
        custodyClass: CustodyClass.software,
        reason: AnchorReason.rotation,
        createdAt: g.createdAt.add(const Duration(days: 1)),
        prevAnchorCid: g.computeCid(),
        sig: 'cafe',
      );
      final result = IdentityAnchorChain.verify([g, future]);
      expect(result.isValid, isFalse);
      expect(result.error, AnchorChainError.schemaVersionUnsupported);
    });
  });
}
