/// Signs Lexicon records for AT Protocol repo commits (V2.0).
///
/// Replaces ZkpProver from V1.x.
/// Signs via Rust Ed25519 over the DAG-CBOR encoding of the record.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ansible_did/ansible_did.dart';
import 'lexicon_record.dart';

abstract class LexiconSigner {
  /// Sign a Lexicon record and return a [SignedLexiconRecord].
  ///
  /// [record] — a JSON map representing the Lexicon record (must include \$type)
  /// [authorDid] — the DID of the author (used to tag the signed record)
  Future<SignedLexiconRecord> sign(
    Map<String, dynamic> record, {
    required String authorDid,
  });
}

/// Concrete implementation that signs via Rust FFI.
///
/// Pipeline:
///   1. Build [LexiconRecord] struct from the map
///   2. [RustLib.instance.apiCborEncodeRecord] → Uint8List (DAG-CBOR bytes)
///   3. [RustLib.instance.apiComputeCid]       → CIDv1 string
///   4. Load private key from FlutterSecureStorage
///   5. [RustLib.instance.apiSignCommit]       → 64-byte Ed25519 sig (hex)
///   6. Return [SignedLexiconRecord]
///
/// Storage key note: private key is stored under [_kPrivateKeyStorageKey]
/// which must match the key used by [DidPlcManagerImpl] / [DidManagerImpl].
class LexiconSignerImpl implements LexiconSigner {
  final FlutterSecureStorage _secureStorage;
  final bool _allowInsecureFallback;

  // Must match the key written by DidPlcManagerImpl ('ansible_plc_private_key')
  // and the fallback DidManagerImpl ('ansible_did_private_key').
  // We read plc key first; fall back to legacy did key for backward compat.
  static const _kPlcPrivateKeyStorageKey = 'ansible_plc_private_key';
  static const _kLegacyPrivateKeyStorageKey = 'ansible_did_private_key';

  LexiconSignerImpl({
    FlutterSecureStorage? secureStorage,
    bool allowInsecureFallback = const bool.fromEnvironment(
      'ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK',
      defaultValue: false,
    ),
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _allowInsecureFallback = allowInsecureFallback;

  @override
  Future<SignedLexiconRecord> sign(
    Map<String, dynamic> record, {
    required String authorDid,
  }) async {
    try {
      // Build the Rust LexiconRecord struct from the JSON map
      final rustRecord = LexiconRecord(
        type_: record[r'$type'] as String? ?? '',
        text: record['text'] as String? ?? '',
        createdAt: record['createdAt'] as String? ?? '',
        replyTo: record['replyTo'] as String?,
      );

      // Step 1: encode to DAG-CBOR → Uint8List (NOT a hex string)
      final Uint8List cborBytes = await RustLib.instance.apiCborEncodeRecord(
        record: rustRecord,
      );

      // Step 2: compute CID from bytes
      final cid = RustLib.instance.apiComputeCid(cborBytes: cborBytes);

      // Step 3: load private key — prefer plc key, fall back to legacy did key
      final privateKeyHex =
          await _secureStorage.read(key: _kPlcPrivateKeyStorageKey) ??
          await _secureStorage.read(key: _kLegacyPrivateKeyStorageKey);
      if (privateKeyHex == null) {
        throw StateError(
          'No local DID keypair found. Run identity registration first.',
        );
      }

      // Step 4: sign the CBOR bytes with Ed25519
      final commitSigHex = await RustLib.instance.apiSignCommit(
        cborBytes: cborBytes,
        privateKeyHex: privateKeyHex,
      );

      _validateProductionSigningOutput(cid, commitSigHex);

      return SignedLexiconRecord(
        record: record,
        cid: cid,
        commitSigHex: commitSigHex,
        authorDid: authorDid,
      );
    } on UnimplementedError catch (e) {
      if (!_allowInsecureFallback) {
        throw StateError(
          'Native Lexicon signing is not available. Enable only the explicit development signing fallback for local tests.',
        );
      }
      debugPrint(
        '[LexiconSigner] DEV WARNING: Rust signing APIs not implemented — '
        'returning stub signature. Error: $e',
      );
      return _stubSign(record, authorDid: authorDid);
    }
  }

  void _validateProductionSigningOutput(String cid, String commitSigHex) {
    if (_allowInsecureFallback) return;

    final usesDevelopmentFallback =
        cid.startsWith('bafydev') ||
        cid.contains('stub') ||
        commitSigHex.startsWith('devsig') ||
        commitSigHex.startsWith('deadbeef');
    final validEd25519Hex = RegExp(
      r'^[0-9a-fA-F]{128}$',
    ).hasMatch(commitSigHex);

    if (usesDevelopmentFallback || !validEd25519Hex) {
      throw StateError(
        'Native Lexicon signing returned a development signing fallback. '
        'Bundle the production Rust signer before publishing records.',
      );
    }
  }

  SignedLexiconRecord _stubSign(
    Map<String, dynamic> record, {
    required String authorDid,
  }) {
    return SignedLexiconRecord(
      record: record,
      cid: 'bafydev-stub-cid',
      commitSigHex:
          'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      authorDid: authorDid,
    );
  }
}

/// Dev stub — returns a fake CID and signature without touching Rust or storage.
///
/// Suitable for CI / widget tests where native plugins are unavailable.
class LexiconSignerStub implements LexiconSigner {
  @override
  Future<SignedLexiconRecord> sign(
    Map<String, dynamic> record, {
    required String authorDid,
  }) async {
    debugPrint(
      '[LexiconSignerStub] sign called — returning dev stub signature',
    );
    return SignedLexiconRecord(
      record: record,
      cid: 'bafydev-stub-cid-${record[r'$type'] ?? 'unknown'}',
      commitSigHex:
          'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      authorDid: authorDid,
    );
  }
}
