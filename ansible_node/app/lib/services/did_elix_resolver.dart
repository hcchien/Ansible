import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

/// A `did:elix` resolved from the federation, with the Relay and verified
/// genesis-to-active chain that supplied it.
class ResolvedIdentity {
  final IdentityAnchor anchor;
  final List<IdentityAnchor> chain;
  final String resolvedVia;

  const ResolvedIdentity({
    required this.anchor,
    required this.chain,
    required this.resolvedVia,
  });

  String? get didKey =>
      anchor.alsoKnownAs.where((a) => a.startsWith('did:key:')).firstOrNull;

  String? get didPlc =>
      anchor.alsoKnownAs.where((a) => a.startsWith('did:plc:')).firstOrNull;
}

/// Monotonic active-chain checkpoints used to reject a valid-but-stale Relay
/// response after the resolver has already observed a newer signed successor.
/// Applications can inject a persistent implementation; the default retains
/// checkpoints for the lifetime of this resolver instance without publishing
/// resolution history or making a Relay authoritative.
abstract interface class DidElixCheckpointStore {
  Future<List<String>?> load(String did);

  Future<void> save(String did, List<String> chainCids);
}

class InMemoryDidElixCheckpointStore implements DidElixCheckpointStore {
  final Map<String, List<String>> _chains = {};

  @override
  Future<List<String>?> load(String did) async {
    final chain = _chains[did];
    return chain == null ? null : List<String>.unmodifiable(chain);
  }

  @override
  Future<void> save(String did, List<String> chainCids) async {
    _chains[did] = List<String>.unmodifiable(chainCids);
  }
}

/// Fail-closed, full-chain `did:elix` resolver.
///
/// Every Relay answer is treated as untrusted input. The resolver checks the
/// genesis derivation, canonical CIDs, every link, every current-key
/// signature, device attestations, and each previous-authority transition
/// proof before returning the active anchor. Legacy Relays without the chain
/// endpoint are supported only for an unrotated legacy genesis anchor.
class DidElixResolver {
  final List<String> relays;
  final http.Client _client;
  final DidElixCheckpointStore _checkpointStore;

  DidElixResolver({
    required this.relays,
    http.Client? client,
    DidElixCheckpointStore? checkpointStore,
  }) : _client = client ?? http.Client(),
       _checkpointStore = checkpointStore ?? InMemoryDidElixCheckpointStore();

  Future<ResolvedIdentity?> resolve(String did) async {
    final candidates = <ResolvedIdentity>[];
    for (final relay in relays) {
      final base = relay.endsWith('/')
          ? relay.substring(0, relay.length - 1)
          : relay;
      try {
        final candidate = await _resolveFromRelay(base, did);
        if (candidate != null) candidates.add(candidate);
      } catch (_) {
        // A malformed, unverifiable, or unreachable Relay is skipped.
      }
    }

    final selected = _selectConsistentLongest(candidates);
    if (selected == null) return null;
    final cids = selected.chain.map((anchor) => anchor.computeCid()).toList();
    final checkpoint = await _checkpointStore.load(did);
    if (checkpoint != null && !_isPrefix(checkpoint, cids)) return null;
    await _checkpointStore.save(did, cids);
    return selected;
  }

  Future<ResolvedIdentity?> _resolveFromRelay(String base, String did) async {
    final encodedDid = Uri.encodeComponent(did);
    final chainResponse = await _client.get(
      Uri.parse('$base/api/v1/identity/chain/$encodedDid'),
    );
    if (chainResponse.statusCode == 200) {
      final decoded = jsonDecode(chainResponse.body) as Map;
      final rawAnchors = (decoded['anchors'] as List)
          .map((value) => (value as Map).cast<String, Object?>())
          .toList(growable: false);
      final anchors = rawAnchors
          .map(IdentityAnchor.fromMap)
          .toList(growable: false);
      if (await _verifiedChain(did, anchors, rawAnchors)) {
        return ResolvedIdentity(
          anchor: anchors.last,
          chain: anchors,
          resolvedVia: base,
        );
      }
      return null;
    }

    // Compatibility for an older Relay: active-only resolution is safe only
    // for an unrotated legacy genesis object.
    final activeResponse = await _client.get(
      Uri.parse('$base/api/v1/identity/anchor/$encodedDid'),
    );
    if (activeResponse.statusCode != 200) return null;
    final raw = (jsonDecode(activeResponse.body) as Map)
        .cast<String, Object?>();
    final anchor = IdentityAnchor.fromMap(raw);
    if (anchor.schemaVersion < 4 &&
        anchor.reason == AnchorReason.initial &&
        anchor.prevAnchorCid == null &&
        await _verifiedChain(did, [anchor], [raw])) {
      return ResolvedIdentity(
        anchor: anchor,
        chain: [anchor],
        resolvedVia: base,
      );
    }
    return null;
  }

  ResolvedIdentity? _selectConsistentLongest(
    List<ResolvedIdentity> candidates,
  ) {
    if (candidates.isEmpty) return null;
    var selected = candidates.first;
    var selectedCids = selected.chain
        .map((anchor) => anchor.computeCid())
        .toList();
    for (final candidate in candidates.skip(1)) {
      final candidateCids = candidate.chain
          .map((anchor) => anchor.computeCid())
          .toList();
      if (_isPrefix(selectedCids, candidateCids)) {
        if (candidateCids.length > selectedCids.length) {
          selected = candidate;
          selectedCids = candidateCids;
        }
      } else if (!_isPrefix(candidateCids, selectedCids)) {
        // Two independently valid but divergent successors are equivocation;
        // no Relay ordering is allowed to pick a winner silently.
        return null;
      }
    }
    return selected;
  }

  bool _isPrefix(List<String> prefix, List<String> chain) {
    if (prefix.length > chain.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (prefix[index] != chain[index]) return false;
    }
    return true;
  }

  Future<bool> _verifiedChain(
    String did,
    List<IdentityAnchor> anchors,
    List<Map<String, Object?>> rawAnchors,
  ) async {
    if (anchors.isEmpty || anchors.length != rawAnchors.length) return false;
    if (!IdentityAnchorChain.verify(anchors).isValid) return false;
    if (anchors.any((anchor) => anchor.did != did)) return false;

    final genesis = anchors.first;
    if (!_genesisMatches(did, genesis)) return false;
    final commitment = genesis.genesisCommitment;

    for (var index = 0; index < anchors.length; index++) {
      final anchor = anchors[index];
      final raw = rawAnchors[index];
      if (raw['anchor_cid'] case final String servedCid) {
        if (servedCid != anchor.computeCid()) return false;
      }
      if (commitment != null &&
          (anchor.schemaVersion != 4 ||
              !_sameCommitment(commitment, anchor.genesisCommitment))) {
        return false;
      }
      if (!await _verifyAnchor(anchor)) return false;

      if (index > 0) {
        final previous = anchors[index - 1];
        final authorization = anchor.reason == AnchorReason.recovery
            ? raw['recovery_proof'] as String?
            : anchor.deviceSig;
        if (!await _verifyTransition(previous, anchor, authorization)) {
          return false;
        }
      }
    }
    return true;
  }

  bool _genesisMatches(String did, IdentityAnchor genesis) {
    final commitment = genesis.genesisCommitment;
    if (genesis.schemaVersion >= 4) {
      if (commitment == null ||
          commitment['method'] != 'did:elix' ||
          commitment['method_version'] != 1 ||
          commitment['genesis_key'] != genesis.identityKey) {
        return false;
      }
      return deriveDidElixV1(
            genesisKey: commitment['genesis_key'] as String? ?? '',
            genesisNonceHex: commitment['genesis_nonce'] as String? ?? '',
          ) ==
          did;
    }
    return deriveDidElix(
          identityKey: genesis.identityKey,
          handle: genesis.handle,
          custodyClass: genesis.custodyClass,
          identityKeyAlgorithm: genesis.identityKeyAlgorithm,
        ) ==
        did;
  }

  bool _sameCommitment(
    Map<String, Object?> expected,
    Map<String, Object?>? actual,
  ) {
    if (actual == null) return false;
    return expected['method'] == actual['method'] &&
        expected['method_version'] == actual['method_version'] &&
        expected['genesis_key'] == actual['genesis_key'] &&
        expected['genesis_nonce'] == actual['genesis_nonce'];
  }

  Future<bool> _verifyAnchor(IdentityAnchor anchor) async {
    if (!await _verifySignature(
      algorithm: anchor.identityKeyAlgorithm,
      publicKeyHex: anchor.identityKey,
      message: utf8.encode(anchor.canonicalBodyJson()),
      signatureHex: anchor.sig,
    )) {
      return false;
    }
    for (final device in anchor.devices) {
      if (!await _verifySignature(
        algorithm: anchor.identityKeyAlgorithm,
        publicKeyHex: anchor.identityKey,
        message: DeviceKey.attestationMessageFor(
          deviceId: device.deviceId,
          deviceKeyHex: device.deviceKey,
          custodyClass: device.custodyClass,
          enrolledAt: device.enrolledAt,
        ),
        signatureHex: device.attestationSig,
      )) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _verifyTransition(
    IdentityAnchor previous,
    IdentityAnchor current,
    String? authorization,
  ) async {
    if (authorization == null || authorization.isEmpty) return false;
    final sameKey =
        previous.identityKeyAlgorithm == current.identityKeyAlgorithm &&
        previous.identityKey == current.identityKey;
    final reasonMatches = switch (current.reason) {
      AnchorReason.initial => false,
      AnchorReason.rotation => !sameKey,
      AnchorReason.recovery => current.schemaVersion < 4 || !sameKey,
      AnchorReason.deviceChange =>
        sameKey && previous.custodyClass == current.custodyClass,
    };
    if (!reasonMatches) return false;
    final body = utf8.encode(current.canonicalBodyJson());

    if (await _verifySignature(
      algorithm: previous.identityKeyAlgorithm,
      publicKeyHex: previous.identityKey,
      message: body,
      signatureHex: authorization,
    )) {
      return true;
    }
    if (current.reason == AnchorReason.rotation) return false;
    for (final device in previous.devices) {
      if (await _verifySignature(
        algorithm: 'ed25519',
        publicKeyHex: device.deviceKey,
        message: body,
        signatureHex: authorization,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _verifySignature({
    required String algorithm,
    required String publicKeyHex,
    required List<int> message,
    required String signatureHex,
  }) async {
    if (signatureHex.isEmpty) return false;
    if (algorithm == 'ed25519') {
      return Ed25519Keys.verify(
        publicKeyHex: publicKeyHex,
        message: message,
        sigHex: signatureHex,
      );
    }
    if (algorithm == 'p256-sha256') {
      return DidSigner.verify(
        publicKeyHex: publicKeyHex,
        message: message,
        signature: Ed25519Signature(signatureHex),
      );
    }
    return false;
  }

  void close() => _client.close();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
