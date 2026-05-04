/// ansible_vc — Verifiable Credentials for Tris-Aura
///
/// V2.0 (active): W3C VC / VP + Passkeys + AT Protocol Lexicon signing
///   [VerifiableCredential] / [VerifiablePresentation] — W3C VC Data Model
///   [CredentialWallet]     — FlutterSecureStorage VC persistence
///   [VpBuilder]            — build + sign VP from stored VCs
///   [LexiconRecord]        — io.trisaura.* record types
///   [LexiconSigner]        — Ed25519 CBOR record signing
///
/// V1.1 (superseded): NFC passport + ZKP Groth16
///   [PassportData] / [SelfIssuedVc] / [ZkpProof] / [Nullifier] — kept for
///   backward compatibility; deactivated from the main app flow.

library ansible_vc;

// V2.0 — W3C VC / VP
export 'src/verifiable_credential.dart';
export 'src/vp_builder.dart';

// V2.0 — AT Protocol Lexicon
export 'src/lexicon_record.dart';
export 'src/lexicon_signer.dart';

// V1.1 — NFC + ZKP (superseded, kept for reference)
export 'src/passport_data.dart';
export 'src/nfc_passport_reader.dart';
export 'src/self_issued_vc.dart';
export 'src/zkp_proof.dart';
export 'src/nullifier.dart';
