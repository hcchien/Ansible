/// Unified entrypoint for the generated flutter_rust_bridge API.
///
/// The generated code (lib/src/rust/) exposes the Rust functions as top-level
/// functions split across api*.dart files, and the data types in their own
/// files. This module re-exports the public surface and provides a thin
/// compatibility extension so existing call sites that use the historical
/// `RustLib.instance.apiX(...)` method-style API keep working.
library;

export 'rust/frb_generated.dart' show RustLib;
export 'rust/api.dart';
export 'rust/api_atproto.dart';
export 'rust/api_zkp.dart';
export 'rust/api_crdt.dart';
export 'rust/api_messenger.dart';
export 'rust/did_key.dart';
export 'rust/messenger.dart';
export 'rust/atproto/did_plc.dart';
export 'rust/atproto/lexicon.dart';

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'rust/frb_generated.dart';
import 'rust/api.dart' as _api;
import 'rust/api_atproto.dart' as _atproto;
import 'rust/api_zkp.dart' as _zkp;
import 'rust/api_crdt.dart' as _crdt;
import 'rust/api_messenger.dart' as _msg;
import 'rust/did_key.dart';
import 'rust/messenger.dart';
import 'rust/atproto/did_plc.dart';
import 'rust/atproto/lexicon.dart';

/// Initialise the Rust bridge with the correct library loader per platform.
///
/// iOS and macOS statically link `libansible_rust_core.a` (via `-force_load` in
/// the platform podspecs), so there is no dynamic library to open — the FFI
/// symbols live in the app binary and must be resolved from the running process.
/// Other platforms (Android `.so`, Linux `.so`) use frb's default stem-based
/// loader.
Future<void> initRustBridge() async {
  if (Platform.isIOS || Platform.isMacOS) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await RustLib.init();
  }
}

/// Maps the historical method-style API onto the generated free functions, so
/// callers can keep using `RustLib.instance.apiX(...)`.
extension RustLibCompat on RustLib {
  // ── core (api.dart) ──────────────────────────────────────────────────────
  KeyPairBytes apiGenerateKeypair() => _api.apiGenerateKeypair();

  String apiDecodeDidKey({required String did}) =>
      _api.apiDecodeDidKey(did: did);

  String apiEncodeDidKey({required String publicKeyHex}) =>
      _api.apiEncodeDidKey(publicKeyHex: publicKeyHex);

  Future<String> apiSignMessage({
    required String privateKeyHex,
    required String messageHex,
  }) =>
      _api.apiSignMessage(privateKeyHex: privateKeyHex, messageHex: messageHex);

  bool apiVerifySignature({
    required String publicKeyHex,
    required String messageHex,
    required String signatureHex,
  }) => _api.apiVerifySignature(
    publicKeyHex: publicKeyHex,
    messageHex: messageHex,
    signatureHex: signatureHex,
  );

  // ── atproto (api_atproto.dart) ───────────────────────────────────────────
  PlcGenesisOp apiCreateDidPlc({
    required String signingKeyHex,
    required String handle,
    required String pdsEndpoint,
  }) => _atproto.apiCreateDidPlc(
    signingKeyHex: signingKeyHex,
    handle: handle,
    pdsEndpoint: pdsEndpoint,
  );

  Future<Uint8List> apiCborEncodeRecord({required LexiconRecord record}) =>
      _atproto.apiCborEncodeRecord(record: record);

  String apiComputeCid({required List<int> cborBytes}) =>
      _atproto.apiComputeCid(cborBytes: cborBytes);

  Future<String> apiSignCommit({
    required List<int> cborBytes,
    required String privateKeyHex,
  }) => _atproto.apiSignCommit(
    cborBytes: cborBytes,
    privateKeyHex: privateKeyHex,
  );

  // ── zkp (api_zkp.dart) ───────────────────────────────────────────────────
  Future<_zkp.ZkpResult> apiZkpGenerateProof({
    required String passportSecretHex,
  }) => _zkp.apiZkpGenerateProof(passportSecretHex: passportSecretHex);

  Future<bool> apiZkpVerifyProof({
    required String proofHex,
    required String nullifierHex,
  }) => _zkp.apiZkpVerifyProof(proofHex: proofHex, nullifierHex: nullifierHex);

  String apiZkpComputeNullifier({required String passportSecretHex}) =>
      _zkp.apiZkpComputeNullifier(passportSecretHex: passportSecretHex);

  // ── crdt (api_crdt.dart) ─────────────────────────────────────────────────
  void apiCrdtInitDoc({required String entityId}) =>
      _crdt.apiCrdtInitDoc(entityId: entityId);

  String apiCrdtInsertText({
    required String entityId,
    required String fieldName,
    required String content,
  }) => _crdt.apiCrdtInsertText(
    entityId: entityId,
    fieldName: fieldName,
    content: content,
  );

  void apiCrdtApplyDelta({
    required String entityId,
    required String payloadB64,
  }) => _crdt.apiCrdtApplyDelta(entityId: entityId, payloadB64: payloadB64);

  String apiCrdtGetText({
    required String entityId,
    required String fieldName,
  }) => _crdt.apiCrdtGetText(entityId: entityId, fieldName: fieldName);

  // ── messenger (api_messenger.dart) ───────────────────────────────────────
  MessengerDevice apiMessengerCreateDevice({required String subjectDid}) =>
      _msg.apiMessengerCreateDevice(subjectDid: subjectDid);

  List<MessengerPreKey> apiMessengerGeneratePreKeys({
    required MessengerDevice device,
    required int count,
  }) => _msg.apiMessengerGeneratePreKeys(device: device, count: count);

  Future<MessengerCiphertext> apiMessengerEncryptInitialMessage({
    required MessengerEncryptInput input,
  }) => _msg.apiMessengerEncryptInitialMessage(input: input);

  Future<MessengerPlaintext> apiMessengerDecryptInboundMessage({
    required MessengerDevice localDevice,
    required MessengerCiphertext ciphertext,
  }) => _msg.apiMessengerDecryptInboundMessage(
    localDevice: localDevice,
    ciphertext: ciphertext,
  );
}
