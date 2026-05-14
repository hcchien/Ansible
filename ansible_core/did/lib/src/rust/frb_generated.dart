import 'dart:convert';
import 'dart:typed_data';

/// Development fallback for the flutter_rust_bridge output.
///
/// The real generated file should be produced by `./setup_codegen.sh`. This
/// stub keeps the Flutter app buildable while native Rust bindings are being
/// wired up, and mirrors only the API surface used by the Dart packages.
class RustLib {
  RustLib._();

  static final RustLib instance = RustLib._();

  static Future<void> init() async {}

  KeyPairBytes apiGenerateKeypair() {
    const publicKeyHex =
        '0000000000000000000000000000000000000000000000000000000000000000';
    return const KeyPairBytes(
      privateKeyHex:
          '1111111111111111111111111111111111111111111111111111111111111111',
      publicKeyHex: publicKeyHex,
      did: 'did:key:dev-placeholder',
    );
  }

  String apiDecodeDidKey({required String did}) {
    return '0000000000000000000000000000000000000000000000000000000000000000';
  }

  String apiEncodeDidKey({required String publicKeyHex}) {
    return 'did:key:dev-${publicKeyHex.substring(0, 8)}';
  }

  Future<String> apiSignMessage({
    required String privateKeyHex,
    required String messageHex,
  }) async {
    return 'dev-signature-${messageHex.substring(0, messageHex.length.clamp(0, 16))}';
  }

  bool apiVerifySignature({
    required String publicKeyHex,
    required String messageHex,
    required String signatureHex,
  }) {
    return signatureHex.startsWith('dev-signature-');
  }

  void apiCrdtInitDoc({required String entityId}) {}

  String apiCrdtInsertText({
    required String entityId,
    required String fieldName,
    required String content,
  }) {
    return base64Encode(utf8.encode(jsonEncode({fieldName: content})));
  }

  Future<ZkpResult> apiZkpGenerateProof({
    required String passportSecretHex,
  }) async {
    final prefix = passportSecretHex.substring(
      0,
      passportSecretHex.length.clamp(0, 16),
    );
    return ZkpResult(
      proofHex: 'dev-proof-$prefix',
      nullifierHex: 'dev-nullifier-$prefix',
      vkHash: 'dev-vk-hash-placeholder',
    );
  }

  Future<bool> apiZkpVerifyProof({
    required String proofHex,
    required String nullifierHex,
  }) async {
    return proofHex.startsWith('dev-proof-');
  }

  String apiZkpComputeNullifier({required String passportSecretHex}) {
    return 'dev-nullifier-${passportSecretHex.substring(0, passportSecretHex.length.clamp(0, 16))}';
  }

  // -------------------------------------------------------------------------
  // V2.0 AT Protocol APIs (P1 — stubs until Rust codegen runs)
  // -------------------------------------------------------------------------

  /// Create a did:plc genesis operation.
  /// Returns a [DidPlcBytes] with the did:plc string and the JSON genesis op.
  Future<DidPlcBytes> apiCreateDidPlc({
    required String signingKeyHex,
    required String handle,
    required String pdsEndpoint,
  }) async {
    final did =
        'did:plc:${_localPlcSuffix('$signingKeyHex|$handle|$pdsEndpoint')}';
    return DidPlcBytes(
      did: did,
      genesisJson: jsonEncode({
        'handle': handle,
        'prev': null,
        'rotationKeys': [signingKeyHex],
        'services': {
          'atproto_pds': {'type': 'AtprotoPds', 'endpoint': pdsEndpoint},
        },
        'signingKey': signingKeyHex,
        'stub': true,
        'type': 'plc_genesis',
      }),
    );
  }

  /// Encode a Lexicon record as DAG-CBOR bytes.
  /// Returns [Uint8List] — matches frb codegen output for Rust Vec<u8>.
  Future<Uint8List> apiCborEncodeRecord({required LexiconRecord record}) async {
    // Dev stub: return a JSON-encoded fallback as raw bytes
    final json = jsonEncode({
      r'$type': record.type_,
      'text': record.text,
      'createdAt': record.createdAt,
      if (record.replyTo != null) 'replyTo': record.replyTo,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Compute a DAG-CBOR CID over the provided CBOR bytes.
  /// Sync function — matches #[frb(sync)] in Rust.
  String apiComputeCid({required Uint8List cborBytes}) {
    // Dev stub: return a fake CIDv1 string based on byte length
    return 'bafydevstub${cborBytes.length.toRadixString(16).padLeft(8, "0")}';
  }

  /// Sign a repo commit (CBOR bytes) with the given private key.
  /// Returns a hex-encoded 64-byte Ed25519 signature.
  Future<String> apiSignCommit({
    required Uint8List cborBytes,
    required String privateKeyHex,
  }) async {
    // Dev stub: deterministic fake sig
    final lenHex = cborBytes.length.toRadixString(16).padLeft(4, '0');
    return 'devsig$lenHex${'00' * 60}';
  }

  Future<MessengerDevice> apiMessengerCreateDevice({
    required String subjectDid,
  }) async {
    return MessengerDevice(
      subjectDid: subjectDid,
      deviceId: 'msgdev_dev_${_localPlcSuffix(subjectDid).substring(0, 12)}',
      identityKeyPublic: 'dev_identity_public_$subjectDid',
      identityKeyPrivate: 'secure:dev_identity_private_$subjectDid',
      signedPreKeyId: 1,
      signedPreKeyPublic: 'dev_signed_pre_key_public_$subjectDid',
      signedPreKeyPrivate: 'secure:dev_signed_pre_key_private_$subjectDid',
      signedPreKeySignature: 'dev_signed_pre_key_signature_$subjectDid',
      sessionState: null,
      oneTimePreKeys: const [],
      nextPreKeyId: 1,
    );
  }

  Future<List<MessengerPreKey>> apiMessengerGeneratePreKeys({
    required MessengerDevice device,
    required int count,
  }) async {
    return [
      for (var i = 0; i < count; i += 1)
        MessengerPreKey(
          preKeyId: device.nextPreKeyId + i,
          publicKey: 'dev_pre_key_public_${device.deviceId}_$i',
          privateKey: 'secure:dev_pre_key_private_${device.deviceId}_$i',
        ),
    ];
  }

  String _localPlcSuffix(String seed) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    final buffer = StringBuffer();
    for (var i = 0; i < 24; i++) {
      final codeUnit = seed.codeUnitAt(i % seed.length);
      buffer.writeCharCode(
        alphabet.codeUnitAt((codeUnit + i) % alphabet.length),
      );
    }
    return buffer.toString();
  }
}

class KeyPairBytes {
  final String privateKeyHex;
  final String publicKeyHex;
  final String did;

  const KeyPairBytes({
    required this.privateKeyHex,
    required this.publicKeyHex,
    required this.did,
  });
}

class ZkpResult {
  final String proofHex;
  final String nullifierHex;
  final String vkHash;

  const ZkpResult({
    required this.proofHex,
    required this.nullifierHex,
    required this.vkHash,
  });
}

/// Result of apiCreateDidPlc — the did:plc string and JSON genesis op.
class DidPlcBytes {
  final String did;
  final String genesisJson;

  const DidPlcBytes({required this.did, required this.genesisJson});
}

class MessengerDevice {
  final String subjectDid;
  final String deviceId;
  final String identityKeyPublic;
  final String identityKeyPrivate;
  final int signedPreKeyId;
  final String signedPreKeyPublic;
  final String signedPreKeyPrivate;
  final String signedPreKeySignature;
  final String? sessionState;
  final List<MessengerPreKey> oneTimePreKeys;
  final int nextPreKeyId;

  const MessengerDevice({
    required this.subjectDid,
    required this.deviceId,
    required this.identityKeyPublic,
    required this.identityKeyPrivate,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeyPrivate,
    required this.signedPreKeySignature,
    required this.sessionState,
    required this.oneTimePreKeys,
    required this.nextPreKeyId,
  });
}

class MessengerPreKey {
  final int preKeyId;
  final String publicKey;
  final String privateKey;

  const MessengerPreKey({
    required this.preKeyId,
    required this.publicKey,
    required this.privateKey,
  });
}

/// Input struct for apiCborEncodeRecord — mirrors the Rust LexiconRecord frb struct.
class LexiconRecord {
  /// Record type string (e.g. 'io.trisaura.post')
  final String type_;

  /// Primary text content
  final String text;

  /// ISO-8601 creation timestamp
  final String createdAt;

  /// Optional AT-URI of parent record (reply)
  final String? replyTo;

  const LexiconRecord({
    required this.type_,
    required this.text,
    required this.createdAt,
    this.replyTo,
  });
}
