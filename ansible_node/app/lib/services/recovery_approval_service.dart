import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';

import 'identity_anchor_service.dart';
import 'relay_anchor_client.dart';
import 'secure_device_key_store.dart';

/// Multi-device QR approve-from-other-device (recovery design flow 3a):
/// a NEW device with no backup generates a fresh identity key and a
/// `recovery` re-anchor; an OLD enrolled device scans the request as a QR,
/// the user confirms, and the old device's DEVICE key signs the
/// `recovery_proof` and submits — the relay then holds the re-anchor in its
/// 72h grace window (hijack resistance still applies; other enrolled
/// devices are alerted and can veto).
///
/// The QR carries the fully-signed anchor object (the same map
/// `POST /api/v1/identity/anchor` takes, minus `recovery_proof`) so the
/// approving device signs exactly the canonical body the relay will verify.
class RecoveryApprovalService {
  RecoveryApprovalService({
    required this.relayClient,
    DeviceKeyStore? deviceKeyStore,
    DateTime Function()? now,
  }) : deviceKeyStore = deviceKeyStore ?? const SecureDeviceKeyStore(),
       now = now ?? (() => DateTime.now().toUtc());

  final RelayAnchorClient relayClient;
  final DeviceKeyStore deviceKeyStore;
  final DateTime Function() now;

  static const qrType = 'elix.recovery.approve';
  static const qrVersion = 1;

  // ── New device side ────────────────────────────────────────────────────────

  /// Builds the recovery request for [did]/[handle] (resolved by the caller):
  /// fresh identity key + fresh device key, a `recovery` anchor chained onto
  /// the relay's active anchor and signed by the new identity key. Returns
  /// null when the DID has no active anchor on the relay.
  ///
  /// The caller must hold on to [RecoveryApprovalRequest.identitySeedHex] —
  /// it becomes this device's identity key once the grace window promotes
  /// the anchor.
  Future<RecoveryApprovalRequest?> buildRequest({
    required String did,
    required String handle,
  }) async {
    final previous = await relayClient.fetchActiveAnchor(did);
    if (previous == null) return null;

    final identitySeedHex = await Ed25519Keys.generateSeedHex();
    final identityKey = InMemoryIdentityKey(identitySeedHex);
    final identityKeyHex = await identityKey.publicKeyHex();
    final enrolledAt = now();

    final deviceKey = await DeviceKey.generate();
    final attestationSig = await identityKey.sign(
      deviceKey.deviceAttestationMessage(
        custodyClass: CustodyClass.software,
        enrolledAt: enrolledAt,
      ),
    );
    final deviceRecord = deviceKey.toDeviceRecord(
      custodyClass: CustodyClass.software,
      enrolledAt: enrolledAt,
      attestationSigHex: attestationSig,
    );

    final unsigned = IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      // The identity key changes, so the did:key alias is rebuilt for the
      // new key (unlike flow 1, which reinstates the same key).
      alsoKnownAs: buildAlsoKnownAs(
        handle: handle,
        identityKeyHex: identityKeyHex,
      ),
      custodyClass: CustodyClass.software,
      devices: [deviceRecord],
      prevAnchorCid: previous.computeCid(),
      reason: AnchorReason.recovery,
      createdAt: enrolledAt,
      sig: '',
    );
    final sig = await identityKey.sign(
      utf8.encode(unsigned.canonicalBodyJson()),
    );
    final anchor = IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      alsoKnownAs: unsigned.alsoKnownAs,
      custodyClass: CustodyClass.software,
      devices: [deviceRecord],
      prevAnchorCid: unsigned.prevAnchorCid,
      reason: AnchorReason.recovery,
      createdAt: enrolledAt,
      sig: sig,
    );

    return RecoveryApprovalRequest(
      anchor: anchor,
      identitySeedHex: identitySeedHex,
      deviceKey: deviceKey,
    );
  }

  /// True once the request's anchor is pending on the relay (the old device
  /// submitted it) — poll from the QR screen.
  Future<PendingAnchor?> pendingFor(String did) {
    return relayClient.fetchPendingAnchor(did);
  }

  // ── Old (approving) device side ────────────────────────────────────────────

  /// Parses a scanned QR payload into the anchor awaiting approval. Returns
  /// null when the payload is not a recovery-approval QR.
  static IdentityAnchor? parseRequest(String qrPayload) {
    try {
      final decoded = jsonDecode(qrPayload);
      if (decoded is! Map ||
          decoded['t'] != qrType ||
          decoded['v'] != qrVersion) {
        return null;
      }
      final anchorMap = decoded['anchor'];
      if (anchorMap is! Map) return null;
      final anchor = IdentityAnchor.fromMap(anchorMap.cast<String, Object?>());
      if (anchor.reason != AnchorReason.recovery) return null;
      return anchor;
    } catch (_) {
      return null;
    }
  }

  /// Approves [anchor] as the enrolled device for [localDid]: verifies it is
  /// a recovery of OUR identity chained onto the CURRENT active anchor,
  /// signs the canonical body with this device's device key, and submits.
  /// Returns the relay's pending result (grace window).
  ///
  /// Throws [RecoveryApprovalException] on every refusal so the UI can say
  /// exactly why nothing was submitted.
  Future<AnchorSubmitResult> approve({
    required String localDid,
    required IdentityAnchor anchor,
  }) async {
    if (anchor.did != localDid) {
      throw const RecoveryApprovalException('different_identity');
    }
    final active = await relayClient.fetchActiveAnchor(localDid);
    if (active == null) {
      throw const RecoveryApprovalException('no_active_anchor');
    }
    if (anchor.prevAnchorCid != active.computeCid()) {
      // Stale or replayed request — it must chain onto the CURRENT anchor.
      throw const RecoveryApprovalException('stale_request');
    }
    final deviceKey = await deviceKeyStore.load();
    if (deviceKey == null) {
      throw const RecoveryApprovalException('no_device_key');
    }

    final recoveryProof = await Ed25519Keys.sign(
      deviceKey.privateKeyHex,
      utf8.encode(anchor.canonicalBodyJson()),
    );

    final result = await relayClient.submitAnchor(
      anchor,
      recoveryProof: recoveryProof,
    );
    return result;
  }
}

/// The new device's outstanding recovery request.
class RecoveryApprovalRequest {
  final IdentityAnchor anchor;

  /// The new identity key seed — becomes this device's identity once the
  /// grace window promotes the anchor. Keep it safe until then.
  final String identitySeedHex;
  final DeviceKey deviceKey;

  const RecoveryApprovalRequest({
    required this.anchor,
    required this.identitySeedHex,
    required this.deviceKey,
  });

  /// The QR payload the old device scans: the full signed anchor object.
  String toQrPayload() {
    return jsonEncode({
      'v': RecoveryApprovalService.qrVersion,
      't': RecoveryApprovalService.qrType,
      'anchor': anchor.toCanonicalMap(),
    });
  }

  /// Short fingerprint of the NEW identity key for on-screen comparison
  /// (both devices show it; the user confirms they match).
  String get newKeyFingerprint {
    final hex = anchor.identityKey;
    return hex.length >= 16
        ? '${hex.substring(0, 8)}…${hex.substring(hex.length - 8)}'
        : hex;
  }
}

class RecoveryApprovalException implements Exception {
  final String reason;

  const RecoveryApprovalException(this.reason);

  @override
  String toString() => 'RecoveryApprovalException($reason)';
}
