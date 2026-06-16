import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Base32 lowercase (RFC 4648), no padding — byte-for-byte identical to the
/// rust core `base32_encode_nopad` (alphabet `abcdefghijklmnopqrstuvwxyz234567`)
/// so a `did:elix` suffix derived here matches a future rust implementation.
String _base32NoPad(List<int> data) {
  const alpha = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = StringBuffer();
  var bits = 0;
  var bitCount = 0;
  for (final byte in data) {
    bits = (bits << 8) | (byte & 0xff);
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      out.writeCharCode(alpha.codeUnitAt((bits >> bitCount) & 0x1f));
    }
  }
  if (bitCount > 0) {
    out.writeCharCode(alpha.codeUnitAt((bits << (5 - bitCount)) & 0x1f));
  }
  return out.toString();
}

/// Derive the canonical `did:elix` identifier. `did:elix:<suffix>` where
/// `<suffix>` is base32(SHA-256(stable-fingerprint)[..16]).
///
/// Bound to the **stable** identity fields only — `identity_key`, `handle`,
/// `custody_class` — deliberately NOT timestamps, device records, or the `did`
/// itself. This makes the identifier:
///   - derivable at registration time *and* at genesis-anchor build time to the
///     same value (no chicken-and-egg, no timestamp coupling);
///   - stable across key rotation/recovery (later anchors keep this `did:elix`
///     because it is derived once from these fields);
///   - domain-independent (no operator domain, unlike `did:web`).
///
/// Mirrors `did:plc` in spirit (an opaque hash of identity-defining data) while
/// depending on no external directory. `identity_key` alone guarantees
/// uniqueness; `handle`/`custody_class` are folded in for self-description.
String deriveDidElix({
  required String identityKey,
  required String handle,
  CustodyClass custodyClass = CustodyClass.software,
}) {
  final fingerprint = <String, Object?>{
    'method': 'did:elix',
    'v': 1,
    'identity_key': identityKey,
    'handle': handle,
    'custody_class': custodyClass.storageValue,
  };
  final digest = sha256.convert(utf8.encode(jsonEncode(fingerprint)));
  return 'did:elix:${_base32NoPad(digest.bytes.sublist(0, 16))}';
}

/// Bitcoin/IPFS base58btc alphabet.
const String _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

String _base58btc(List<int> input) {
  var zeros = 0;
  while (zeros < input.length && input[zeros] == 0) {
    zeros++;
  }
  var num = BigInt.zero;
  for (final b in input) {
    num = (num << 8) | BigInt.from(b & 0xff);
  }
  final out = StringBuffer();
  final base = BigInt.from(58);
  while (num > BigInt.zero) {
    final rem = (num % base).toInt();
    out.writeCharCode(_base58Alphabet.codeUnitAt(rem));
    num = num ~/ base;
  }
  final encoded = out.toString().split('').reversed.join();
  return '${'1' * zeros}$encoded';
}

List<int> _hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw ArgumentError('hex string must have an even length');
  }
  final out = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Encode a hex Ed25519 public key as a `did:key` (multibase base58btc of
/// `0xed01 || pubkey`, multibase prefix `z`). Pure-Dart twin of the rust
/// `encode_did_key` so the wallet holder DID matches byte-for-byte.
String encodeDidKeyEd25519(String publicKeyHex) {
  final bytes = _hexToBytes(publicKeyHex);
  if (bytes.length != 32) {
    throw ArgumentError('Ed25519 public key must be 32 bytes');
  }
  final prefixed = <int>[0xed, 0x01, ...bytes];
  return 'did:key:z${_base58btc(prefixed)}';
}

/// Build the `also_known_as` list for an anchor: the AT-style handle, the
/// wallet `did:key` (same root key), and — only after the opt-in Bluesky
/// bridge — a `did:plc`. Never a `did:web`.
List<String> buildAlsoKnownAs({
  required String handle,
  required String identityKeyHex,
  String? didPlc,
}) {
  return [
    'at://$handle',
    encodeDidKeyEd25519(identityKeyHex),
    if (didPlc != null) didPlc,
  ];
}

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

  /// v2 (2026-06-16): adds `also_known_as` and makes `did` a `did:elix`
  /// (was the `did:plc` stub). Bumped together with the layered-identity work.
  static const int currentSchemaVersion = 2;

  final int schemaVersion;

  /// Canonical identity — a `did:elix` (see [deriveDidElix]). Never a
  /// `did:web` (operator-coupled) and never the wallet `did:key`; those live
  /// in [alsoKnownAs].
  final String did;
  final String handle;

  /// Ed25519 identity (content) public key, hex-encoded.
  final String identityKey;

  /// Verifiable aliases of this same identity, bound by being inside the
  /// signed anchor body: `at://<handle>`, the wallet `did:key:…` (the same
  /// root key encoded), and — only after the opt-in Bluesky bridge — a
  /// `did:plc:…`. Bidirectional binding: the alias targets reference back to
  /// this `did:elix`. Never contains a `did:web`.
  final List<String> alsoKnownAs;

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
    this.alsoKnownAs = const [],
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
        'also_known_as': alsoKnownAs,
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
      alsoKnownAs:
          ((map['also_known_as'] as List?) ?? const []).cast<String>(),
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
