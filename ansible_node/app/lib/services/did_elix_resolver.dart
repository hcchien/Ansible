import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

/// A `did:elix` resolved from the federation, with the relay that served it.
class ResolvedIdentity {
  final IdentityAnchor anchor;

  /// The relay base URL the verified answer came from.
  final String resolvedVia;

  const ResolvedIdentity({required this.anchor, required this.resolvedVia});

  /// The wallet/holder `did:key` advertised by this identity, if any.
  String? get didKey =>
      anchor.alsoKnownAs.where((a) => a.startsWith('did:key:')).firstOrNull;

  /// The bridged `did:plc` alias, if the user has opted into Bluesky.
  String? get didPlc =>
      anchor.alsoKnownAs.where((a) => a.startsWith('did:plc:')).firstOrNull;
}

/// Client-side cross-relay `did:elix` resolver (layered identity Phase C, v0).
///
/// Asks each relay in [relays] for the self-certifying anchor and **verifies
/// the answer locally** before trusting it — the relay that served it is not
/// trusted, the math is:
///   1. the returned anchor's `did` equals the requested DID;
///   2. the DID self-certifies — it is the hash of the anchor's own
///      `identity_key` + `handle` ([deriveDidElix]);
///   3. the anchor signature verifies against that `identity_key`.
///
/// v0 limitation (same as the relay [resolver]): self-certification proves the
/// genesis binding, so an identity that has rotated its key cannot be verified
/// from its active anchor alone — that needs the full chain and is a follow-up.
/// The resolver fails safe: an answer it cannot verify is skipped.
class DidElixResolver {
  final List<String> relays;
  final http.Client _client;

  DidElixResolver({required this.relays, http.Client? client})
      : _client = client ?? http.Client();

  /// Resolve [did], trying each relay in order; returns the first verified
  /// answer, or null if none verify.
  Future<ResolvedIdentity?> resolve(String did) async {
    for (final relay in relays) {
      final base = relay.endsWith('/') ? relay.substring(0, relay.length - 1) : relay;
      try {
        final resp = await _client.get(
          Uri.parse('$base/api/v1/identity/anchor/$did'),
        );
        if (resp.statusCode != 200) continue;

        final anchor = IdentityAnchor.fromCanonicalJson(resp.body);
        if (await _verified(did, anchor)) {
          return ResolvedIdentity(anchor: anchor, resolvedVia: base);
        }
      } catch (_) {
        // Try the next relay.
      }
    }
    return null;
  }

  Future<bool> _verified(String did, IdentityAnchor anchor) async {
    if (anchor.did != did) return false;

    // Self-certification: the DID must hash to this anchor's identity key +
    // handle. A relay cannot serve a forged identity under someone else's DID.
    final expected = deriveDidElix(
      identityKey: anchor.identityKey,
      handle: anchor.handle,
      custodyClass: anchor.custodyClass,
    );
    if (expected != did) return false;

    // Signature: the anchor body must be signed by that identity key.
    if (anchor.sig.isEmpty) return false;
    return Ed25519Keys.verify(
      publicKeyHex: anchor.identityKey,
      message: utf8.encode(anchor.canonicalBodyJson()),
      sigHex: anchor.sig,
    );
  }

  void close() => _client.close();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
