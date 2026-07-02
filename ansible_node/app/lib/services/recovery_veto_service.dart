import 'dart:convert';

import 'identity_anchor_service.dart';
import 'relay_anchor_client.dart';

/// Veto UX on enrolled devices (recovery design §hijack resistance,
/// conflict-priority #1): while a `recovery` re-anchor sits in its 72h grace
/// window, every previously-enrolled key can sign a veto that freezes the
/// account. This service is the app-side half — detect a pending recovery for
/// our DID and, on the user's 否決, sign the relay's stored canonical body
/// with this device's identity key.
class RecoveryVetoService {
  RecoveryVetoService({
    required this.relayClient,
    IdentityKey? identityKey,
  }) : identityKey = identityKey ?? const SecureStorageIdentityKey();

  final RelayAnchorClient relayClient;
  final IdentityKey identityKey;

  /// The pending recovery re-anchor for [did], or null when none (also null
  /// on transport errors — the check is a background safety poll and must
  /// never break app startup; the next launch/wake retries).
  Future<PendingAnchor?> checkPending(String did) async {
    try {
      return await relayClient.fetchPendingAnchor(did);
    } catch (_) {
      return null;
    }
  }

  /// Signs the pending anchor's canonical body with this device's identity
  /// key and submits the veto. On success the relay freezes the account for
  /// manual/issuer-assisted resolution. Throws [RelayAnchorException] on
  /// rejection so the UI can tell "already promoted/vetoed" from success.
  Future<void> veto({
    required String did,
    required PendingAnchor pending,
  }) async {
    final signature = await identityKey.sign(
      utf8.encode(pending.canonicalBody),
    );
    await relayClient.vetoPendingAnchor(
      did: did,
      pendingAnchorCid: pending.anchorCid,
      vetoSig: signature,
    );
  }
}
