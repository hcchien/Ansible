import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Self-certifying identity anchor object (design §"Anchor as a
/// Self-Certifying Object", schema_version 1).
///
/// FOUNDATION slice (Task 1, Dart-only). The canonical encoding, CID hashing,
/// and chain verification implemented here are the reference Dart
/// implementation.
///
/// TODO(Task 1, rust/core): the canonical-encoding + chain-verification +
/// (eventually) the Ed25519 signing/verification of these anchors are
/// perf-critical and security-critical and MUST move into
/// `ansible_rust_core` with Dart bindings in a later task. This Dart code is
/// the spec-faithful interim implementation so the app/store can be built and
/// tested now. Signature *content* is modelled and chain-linked here, but
/// cryptographic signature verification against the identity key is delegated
/// to a later task (see [IdentityAnchorChain]).

/// Why this anchor was created (design `reason` field). Permanently recorded
/// in the chain — Constitution Review item 5 (reason-coded re-anchor).
enum AnchorReason {
  initial('initial'),
  rotation('rotation'),
  recovery('recovery'),
  deviceChange('device_change');

  const AnchorReason(this.storageValue);

  final String storageValue;

  static AnchorReason parse(String value) {
    return AnchorReason.values.firstWhere(
      (r) => r.storageValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unknown anchor reason',
      ),
    );
  }
}

/// Custody class of a key (design D1). `software` today; `hardware` is the
/// future opt-in upgrade — same protocol, stronger label.
enum CustodyClass {
  software('software'),
  hardware('hardware');

  const CustodyClass(this.storageValue);

  final String storageValue;

  static CustodyClass parse(String value) {
    return CustodyClass.values.firstWhere(
      (c) => c.storageValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unknown custody class',
      ),
    );
  }
}

/// An enrolled device record carried inside an anchor object. Device keys are
/// software Ed25519, attested by the identity key, and are NEVER backed up.
class AnchorDeviceRecord {
  final String deviceId;

  /// Ed25519 public key of the device, hex-encoded.
  final String deviceKey;

  final CustodyClass custodyClass;

  final DateTime enrolledAt;

  /// Signature by the identity key over this device record, hex-encoded.
  final String attestationSig;

  const AnchorDeviceRecord({
    required this.deviceId,
    required this.deviceKey,
    required this.custodyClass,
    required this.enrolledAt,
    required this.attestationSig,
  });

  /// Canonical map (keys emitted in a fixed order by [IdentityAnchor]).
  Map<String, Object?> toCanonicalMap() => {
        'device_id': deviceId,
        'device_key': deviceKey,
        'custody_class': custodyClass.storageValue,
        'enrolled_at': enrolledAt.toUtc().toIso8601String(),
        'attestation_sig': attestationSig,
      };

  factory AnchorDeviceRecord.fromMap(Map<String, Object?> map) {
    return AnchorDeviceRecord(
      deviceId: map['device_id']! as String,
      deviceKey: map['device_key']! as String,
      custodyClass: CustodyClass.parse(map['custody_class']! as String),
      enrolledAt: DateTime.parse(map['enrolled_at']! as String).toUtc(),
      attestationSig: map['attestation_sig']! as String,
    );
  }
}

/// The anchor object itself. Hash-chained via [prevAnchorCid] so the key
/// history is an auditable, self-certifying chain (design properties).
class IdentityAnchor {
  static const String typeName = 'io.trisaura.identity.anchor';
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String did;
  final String handle;

  /// Ed25519 identity (content) public key, hex-encoded.
  final String identityKey;

  final CustodyClass custodyClass;
  final List<AnchorDeviceRecord> devices;

  /// CID (hash) of the previous anchor object, or null for the genesis
  /// (`initial`) anchor.
  final String? prevAnchorCid;

  final AnchorReason reason;
  final DateTime createdAt;

  /// Signature by the identity key (plus device co-signature when enrolled),
  /// hex-encoded. Modelled now; cryptographic verification deferred (Task 4).
  final String sig;

  /// Optional device co-signature, hex-encoded (high-value ops on multi-device
  /// accounts — design "Signing policy").
  final String? deviceSig;

  const IdentityAnchor({
    this.schemaVersion = currentSchemaVersion,
    required this.did,
    required this.handle,
    required this.identityKey,
    required this.custodyClass,
    this.devices = const [],
    this.prevAnchorCid,
    required this.reason,
    required this.createdAt,
    required this.sig,
    this.deviceSig,
  });

  /// Deterministic canonical map of the *signed body* (everything except the
  /// signatures), keys in a fixed order. Used both for the CID and as the
  /// message the signatures cover.
  Map<String, Object?> toCanonicalBody() => {
        'type': typeName,
        'schema_version': schemaVersion,
        'did': did,
        'handle': handle,
        'identity_key': identityKey,
        'custody_class': custodyClass.storageValue,
        'devices': devices.map((d) => d.toCanonicalMap()).toList(),
        'prev_anchor_cid': prevAnchorCid,
        'reason': reason.storageValue,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  /// Full canonical map including signatures (the on-the-wire / stored form).
  Map<String, Object?> toCanonicalMap() => {
        ...toCanonicalBody(),
        'sig': sig,
        if (deviceSig != null) 'device_sig': deviceSig,
      };

  /// Canonical JSON of the *signed body* — stable, no insignificant
  /// whitespace, fixed key order. This is what gets hashed to a CID and what
  /// the identity key signs.
  ///
  /// TODO(Task 1, rust/core): replace with the rust canonical encoder (DAG-CBOR
  /// or RFC 8785 JCS) once the rust anchor model lands, so Dart and rust agree
  /// byte-for-byte. JSON here is deterministic by construction (fixed key
  /// order, no whitespace).
  String canonicalBodyJson() => jsonEncode(toCanonicalBody());

  /// Full canonical JSON (body + signatures) — the stored blob.
  String canonicalJson() => jsonEncode(toCanonicalMap());

  /// Content identifier of this anchor: SHA-256 of the canonical body,
  /// hex-encoded. Prefixed `sha256:` so the hash function is self-describing
  /// (forward-compatible with a future multihash/CID migration in rust).
  String computeCid() {
    final digest = sha256.convert(utf8.encode(canonicalBodyJson()));
    return 'sha256:${digest.toString()}';
  }

  factory IdentityAnchor.fromCanonicalJson(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    return IdentityAnchor.fromMap(map);
  }

  factory IdentityAnchor.fromMap(Map<String, Object?> map) {
    final type = map['type'];
    if (type != typeName) {
      throw ArgumentError.value(type, 'type', 'Not an identity anchor object');
    }
    final rawDevices = (map['devices'] as List?) ?? const [];
    return IdentityAnchor(
      schemaVersion: (map['schema_version'] as num?)?.toInt() ??
          currentSchemaVersion,
      did: map['did']! as String,
      handle: map['handle']! as String,
      identityKey: map['identity_key']! as String,
      custodyClass: CustodyClass.parse(map['custody_class']! as String),
      devices: rawDevices
          .map((d) => AnchorDeviceRecord.fromMap(
                (d as Map).cast<String, Object?>(),
              ))
          .toList(),
      prevAnchorCid: map['prev_anchor_cid'] as String?,
      reason: AnchorReason.parse(map['reason']! as String),
      createdAt: DateTime.parse(map['created_at']! as String).toUtc(),
      sig: map['sig']! as String,
      deviceSig: map['device_sig'] as String?,
    );
  }
}
