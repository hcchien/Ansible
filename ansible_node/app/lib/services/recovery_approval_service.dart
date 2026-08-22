import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';

import 'identity_anchor_service.dart';
import 'canonical_identity_store.dart';
import 'relay_anchor_client.dart';
import 'secure_device_key_store.dart';

/// Multi-device QR approve-from-other-device (recovery design flow 3a):
/// a NEW device with no backup generates a fresh identity key and a
/// `recovery` re-anchor; an OLD enrolled device scans the request as a QR,
/// the user confirms, and the old device's active IDENTITY key signs the
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
    IdentityKey? approvalIdentityKey,
    IdentityKey? replacementIdentityKey,
    CanonicalIdentityStore? identityStore,
    DateTime Function()? now,
  }) : deviceKeyStore = deviceKeyStore ?? const SecureDeviceKeyStore(),
       approvalIdentityKey = approvalIdentityKey ?? const ActiveIdentityKey(),
       replacementIdentityKey =
           replacementIdentityKey ?? HardwareBackedIdentityKey(),
       identityStore = identityStore ?? const SecureCanonicalIdentityStore(),
       now = now ?? (() => DateTime.now().toUtc());

  final RelayAnchorClient relayClient;
  final DeviceKeyStore deviceKeyStore;
  final IdentityKey approvalIdentityKey;
  final IdentityKey replacementIdentityKey;
  final CanonicalIdentityStore identityStore;
  final DateTime Function() now;

  static const qrType = 'elix.recovery.approve';
  static const qrVersion = 1;

  // ── New device side ────────────────────────────────────────────────────────

  /// Builds the recovery request for [did]/[handle] (resolved by the caller):
  /// fresh identity key + fresh device key, a `recovery` anchor chained onto
  /// the relay's active anchor and signed by the new identity key. Returns
  /// null when the DID has no active anchor on the relay.
  ///
  /// The replacement identity key is generated in platform hardware. Only its
  /// public key and signatures enter this request.
  Future<RecoveryApprovalRequest?> buildRequest({
    required String did,
    required String handle,
  }) async {
    final previous = await relayClient.fetchActiveAnchor(did);
    if (previous == null) return null;

    final identityKey = replacementIdentityKey;
    final identityKeyHex = await identityKey.publicKeyHex();
    final identityAlgorithm = await identityKey.algorithm();
    final identityCustody = await identityKey.custodyClass();
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

    // Preserve surviving approved devices. Their public records are
    // re-attested by the replacement hardware identity key, so the promoted
    // anchor adds this device instead of silently removing every old device.
    final approvedDevices = <AnchorDeviceRecord>[];
    for (final existing in previous.devices) {
      final message = DeviceKey.attestationMessageFor(
        deviceId: existing.deviceId,
        deviceKeyHex: existing.deviceKey,
        custodyClass: existing.custodyClass,
        enrolledAt: existing.enrolledAt,
      );
      approvedDevices.add(
        AnchorDeviceRecord(
          deviceId: existing.deviceId,
          deviceKey: existing.deviceKey,
          custodyClass: existing.custodyClass,
          enrolledAt: existing.enrolledAt,
          attestationSig: await identityKey.sign(message),
        ),
      );
    }
    approvedDevices.add(deviceRecord);

    final unsigned = IdentityAnchor(
      schemaVersion: previous.schemaVersion,
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      // The identity key changes, so the did:key alias is rebuilt for the
      // new key (unlike flow 1, which reinstates the same key).
      alsoKnownAs: identityAlgorithm == 'ed25519'
          ? buildAlsoKnownAs(handle: handle, identityKeyHex: identityKeyHex)
          : ['at://$handle'],
      identityKeyAlgorithm: identityAlgorithm,
      genesisCommitment: previous.genesisCommitment,
      custodyClass: identityCustody,
      devices: approvedDevices,
      prevAnchorCid: previous.computeCid(),
      reason: AnchorReason.recovery,
      createdAt: enrolledAt,
      sig: '',
    );
    final sig = await identityKey.sign(
      utf8.encode(unsigned.canonicalBodyJson()),
    );
    final anchor = IdentityAnchor(
      schemaVersion: unsigned.schemaVersion,
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      identityKeyAlgorithm: identityAlgorithm,
      genesisCommitment: unsigned.genesisCommitment,
      alsoKnownAs: unsigned.alsoKnownAs,
      custodyClass: identityCustody,
      devices: approvedDevices,
      prevAnchorCid: unsigned.prevAnchorCid,
      reason: AnchorReason.recovery,
      createdAt: enrolledAt,
      sig: sig,
    );

    return RecoveryApprovalRequest(anchor: anchor, deviceKey: deviceKey);
  }

  /// Installs only public identity metadata plus the new local device key after
  /// Relay accepts the request as pending. No identity private bytes exist to
  /// export or persist in hardware mode.
  Future<void> installApprovedRequest(RecoveryApprovalRequest request) async {
    await identityStore.save(
      CanonicalIdentity(
        did: request.anchor.did,
        handle: request.anchor.handle,
        publicKeyHex: request.anchor.identityKey,
        signingAlgorithm: request.anchor.identityKeyAlgorithm,
        custody: request.anchor.custodyClass == CustodyClass.hardware
            ? 'hardware'
            : 'reduced_trust',
        genesisCommitment: request.anchor.genesisCommitment,
      ),
    );
    await deviceKeyStore.save(request.deviceKey);
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
  /// signs the canonical body with the currently active identity key, and
  /// submits. In hardware-custody mode this requires platform user presence
  /// (Face ID, Touch ID, or the device passcode).
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
    final recoveryProof = await approvalIdentityKey.sign(
      utf8.encode(anchor.canonicalBodyJson()),
    );

    final result = await relayClient.submitAnchor(
      anchor,
      recoveryProof: recoveryProof,
    );
    return result;
  }

  Future<AnchorSubmitResult> approveWithRecoveryCode({
    required RecoveryApprovalRequest request,
    required String recoveryCode,
  }) {
    if (recoveryCode.trim().isEmpty) {
      throw const RecoveryApprovalException('missing_recovery_code');
    }
    return relayClient.submitAnchorWithRecoveryCode(
      request.anchor,
      recoveryCode: recoveryCode,
    );
  }
}

/// The new device's outstanding recovery request.
class RecoveryApprovalRequest {
  final IdentityAnchor anchor;

  final DeviceKey deviceKey;

  /// Legacy test/compatibility seam. Hardware recovery never sets or persists
  /// exportable identity material.
  final String? identitySeedHex;

  const RecoveryApprovalRequest({
    required this.anchor,
    required this.deviceKey,
    this.identitySeedHex,
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
