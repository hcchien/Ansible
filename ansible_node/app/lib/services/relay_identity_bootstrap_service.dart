import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';

import 'atproto_client.dart';
import 'canonical_identity_store.dart';
import 'relay_handle_store.dart';

/// Ensures a self-custodied DID is known to the selected Relay before the app
/// asks that Relay for a sync capability. Only a Relay-scoped handle, public
/// key, and a user-authorized signature leave the device.
///
/// A Relay is only a projection of the identity, not the identity authority.
/// When switching Relays, the same locally held DID key must re-anchor the
/// handle. A collision is not an identity conflict: the UI must ask the user
/// to choose another handle in that Relay space while retaining the same DID.
class RelayHandleConflict implements Exception {
  const RelayHandleConflict({required this.suggestedSuffix});

  final String suggestedSuffix;
}

class RelayIdentityBootstrapService {
  const RelayIdentityBootstrapService._();

  static Future<String> ensureVerified({
    required String did,
    required String baseUrl,
    String? publicKeyHex,
    DidSigner? signer,
    String? preferredHandleSuffix,
  }) async {
    if (did.trim().isEmpty) {
      throw StateError('missing_did');
    }
    final canonical = await _canonicalIdentityFor(did);
    final resolvedPublicKey = publicKeyHex ?? canonical.publicKeyHex;
    if (resolvedPublicKey.isEmpty) {
      throw StateError('missing_identity_key');
    }

    final handleStore = const SecureRelayHandleStore();
    final storedHandle = await handleStore.load(baseUrl);
    final suffix = _normalizeSuffix(
      preferredHandleSuffix ??
          _suffixFromHandle(storedHandle) ??
          _suffixFromHandle(canonical.handle),
    );
    final client = AtProtoClient(baseUrl: baseUrl);
    try {
      late final RegistrationChallenge challenge;
      try {
        challenge = await client.register(
          publicKeyHex: resolvedPublicKey,
          handleSuffix: suffix,
          signingAlgorithm: canonical.signingAlgorithm,
        );
      } on AtProtoException catch (error) {
        if (error.error == 'handle_taken' || error.error == 'handle_pending') {
          throw RelayHandleConflict(suggestedSuffix: suffix);
        }
        rethrow;
      }
      final handle = challenge.handle;
      if (handle == null || _suffixFromHandle(handle) != suffix) {
        throw StateError('relay_handle_mismatch');
      }
      final signature = await (signer ?? DidSignerImpl()).sign(
        utf8.encode(challenge.nonce),
      );
      final anchored = await client.anchor(
        AnchorRequest(
          did: did,
          publicKeyHex: resolvedPublicKey,
          handle: handle,
          registrationSig: signature.hex,
          nonce: challenge.nonce,
          signingAlgorithm: canonical.signingAlgorithm,
        ),
      );
      if (anchored.did != did || anchored.handle != handle) {
        throw StateError('relay_handle_mismatch');
      }
      await handleStore.save(baseUrl, handle);
      return handle;
    } finally {
      client.close();
    }
  }

  static Future<CanonicalIdentity> _canonicalIdentityFor(String did) async {
    final canonical = await const SecureCanonicalIdentityStore().load();
    if (canonical == null || canonical.did != did) {
      throw StateError('missing_identity_handle');
    }
    return canonical;
  }

  static String? _suffixFromHandle(String? handle) {
    if (handle == null) return null;
    final normalized = handle.trim().toLowerCase();
    final dot = normalized.indexOf('.');
    if (dot <= 0 || dot == normalized.length - 1) return null;
    return normalized.substring(0, dot);
  }

  static String _normalizeSuffix(String? suffix) {
    if (suffix == null) throw StateError('missing_identity_handle');
    final normalized = suffix.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(normalized)) {
      throw StateError('invalid_identity_handle');
    }
    return normalized;
  }
}
